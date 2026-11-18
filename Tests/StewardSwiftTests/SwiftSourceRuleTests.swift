import Foundation
@testable import StewardSwift
import StewardTesting
import Synchronization
import Testing

/// What `Rule.swiftSource` does with each file: the log line, skips,
/// refusals, time limits and errors.
@Suite("Rule.swiftSource")
struct SwiftSourceRuleTests {
    typealias Refusal = SwiftFile.Refusal

    static let good = "func a() {}\n"
    static let broken = "func a( {\n"
    static let deep = "let x = " + String(repeating: "[", count: 22) + "1" + String(repeating: "]", count: 22) + "\n"

    /// A pull request that creates each of `files`.
    static func created(_ files: [String: String]) throws -> Context {
        try SourceChange.context(from: [:], to: files)
    }

    /// A finding at every function, and a failure if `check` is called on
    /// a file named `Never.swift`.
    static let everyFunction: @Sendable (SwiftFile) -> [Finding] = { file in
        file.functions.map { .message($0.name, at: $0.location) }
            + (file.path.hasSuffix("Never.swift") ? [.failure("checked")] : [])
    }

    @Test("the check takes the file alone or the file and the log, by its closure's parameters alone")
    func overloads() async throws {
        let context = try Self.created(["Sources/A.swift": Self.good])
        let alone = Rule.swiftSource("Functions") { file in
            file.functions.map { .message($0.name, at: $0.location) }
        }
        let logged = Rule.swiftSource("Functions") { file, log in
            log.write("Functions: read \(file.path)")
            return file.functions.map { .message($0.name, at: $0.location) }
        }
        let expected: [Finding] = [.message("a", at: Location(path: "Sources/A.swift", line: 1))]
        #expect(try await alone.evaluate(context) == expected)
        #expect(try await logged.evaluate(context) == expected)
    }

    @Test(
        "a file with syntax errors is a skip of the rule's kind, and the check never sees it",
        arguments: [Finding.Kind.warning, .message, .failure]
    )
    func syntaxErrors(kind: Finding.Kind) async throws {
        let context = try Self.created(["Sources/Never.swift": Self.broken])
        let rule = Rule.swiftSource("Functions", reportingSkipsAs: kind, Self.everyFunction)
        #expect(try await rule.evaluate(context)
            == [.skipped("Sources/Never.swift", "with syntax errors", by: "Functions", as: kind)])
    }

    @Test("a file that builds can still be skipped: code for a later compiler in an inactive #if compiler block")
    func inactiveCompilerBlock() async throws {
        let source = """
            #if compiler(>=99)
            let x = future syntax here ) ]
            #endif
            func a() {}

            """
        let context = try Self.created(["Sources/Never.swift": source])
        #expect(try await Rule.swiftSource("Functions", Self.everyFunction).evaluate(context)
            == [.skipped("Sources/Never.swift", "with syntax errors", by: "Functions")])
    }

    @Test("a file over the limit is skipped by Rule.changedFiles, with the kind passed through")
    func overLimit() async throws {
        let context = try Self.created(["Sources/Never.swift": Self.good])
        let rule = Rule.swiftSource("Functions", limit: 4, reportingSkipsAs: .failure, Self.everyFunction)
        let findings = try await rule.evaluate(context)
        #expect(findings.map(\.kind) == [.failure])
        #expect(findings.first?.text.contains("over the limit of 4") == true, "\(findings)")
    }

    @Test("a source nested too deeply is a failure whatever the skip kind, and the rule goes on to the next file")
    func refused() async throws {
        let context = try Self.created(["Sources/Never.swift": Self.deep, "Sources/Z.swift": Self.good])
        let rule = Rule.swiftSource("Functions", reportingSkipsAs: .message, Self.everyFunction)
        let refusal = SwiftFile.Refusal.nestingTooDeep(.squareBrackets, line: 1, limit: 1 << 22)
        #expect(try await rule.evaluate(context) == [
            .failure("Rule “Functions” couldn't read `Sources/Never.swift`. \(refusal)",
                     at: Location(path: "Sources/Never.swift")),
            .message("a", at: Location(path: "Sources/Z.swift", line: 1)),
        ])
    }

    /// A rule that reads each file as `reading` does.
    static func rule(_ reading: SwiftSourceReading) -> Rule {
        Rule.changedFiles(reading.rule, in: "**") { file, log in
            try await reading.findings(for: file, log: log)
        }
    }

    @Test("a reading past its time limit is a failure, and while it runs on, every later file is one too")
    func timedOut() async throws {
        let gate = ParseGate()
        let release = DispatchSemaphore(value: 0)
        var reading = SwiftSourceReading(
            rule: "Functions", scope: .changedDeclarations, skipKind: .message, gate: gate,
            timeLimit: .milliseconds(20)
        ) { _, _ in [.failure("checked")] }
        // A reading that ends only when the test lets it.
        reading.read = { source, changed, scope in
            release.wait()
            return SwiftSourceReading.read(source, changed, scope: scope)
        }
        let context = try Self.created(["Sources/A.swift": Self.good, "Sources/B.swift": Self.good])
        let findings = try await Self.rule(reading).evaluate(context)
        release.signal()
        #expect(findings == [
            .failure(
                "Rule “Functions” couldn't read `Sources/A.swift`. \(Refusal.timedOut(limit: .milliseconds(20)))",
                at: Location(path: "Sources/A.swift")
            ),
            .failure(
                "Rule “Functions” couldn't read `Sources/B.swift`. \(Refusal.earlierParseStillRunning)",
                at: Location(path: "Sources/B.swift")
            ),
        ])
        try await Self.waitUntilOpen(gate)
    }

    @Test("the time limit is the reading's: a slow check isn't cut short, and closes no gate")
    func slowCheck() async throws {
        let gate = ParseGate()
        let reading = SwiftSourceReading(
            rule: "Functions", scope: .changedFiles, skipKind: .message, gate: gate, timeLimit: .seconds(1)
        ) { _, _ in
            Thread.sleep(forTimeInterval: 1.5)
            return [.message("slow")]
        }
        let context = try Self.created(["Sources/A.swift": Self.good])
        #expect(try await Self.rule(reading).evaluate(context) == [.message("slow")])
        #expect(gate.isOpen)
    }

    @Test("what the check throws is the rule's failure, and no file after it is checked")
    func throwing() async throws {
        struct Stop: Error, CustomStringConvertible {
            var description: String { "stop here" }
        }
        let context = try Self.created(["Sources/A.swift": Self.good, "Sources/B.swift": Self.good])
        let checked = Mutex<[String]>([])
        let rule = Rule.swiftSource("Functions") { file in
            checked.withLock { $0.append(file.path) }
            throw Stop()
        }
        await #expect(throws: Stop.self) { try await rule.evaluate(context) }
        #expect(checked.withLock { $0 } == ["Sources/A.swift"])
    }

    @Test("a run logs a line before each file it checks, and one for each it skips, as a Dangerfile runs the rule")
    func log() async throws {
        let context = try Self.created([
            "Sources/A.swift": Self.good,
            "Sources/Broken.swift": Self.broken,
            "Sources/Deep.swift": Self.deep,
        ])
        let outcome = await SwiftRules.run(on: context)
        #expect(outcome.log.contains("""
            Functions: checking Sources/A.swift
            Functions: checking Sources/Broken.swift
            Functions: skipped Sources/Broken.swift, with syntax errors
            Functions: checking Sources/Deep.swift

            """), "\(outcome.log)")
        #expect(outcome.exitStatus == 1)
        #expect(outcome.report?.findings.map(\.kind) == [.message, .warning, .failure])
    }

    /// Waits up to ten seconds for `gate`'s runaway to end.
    static func waitUntilOpen(_ gate: ParseGate) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while !gate.isOpen, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(gate.isOpen, "the runaway didn't end")
    }
}

/// A Dangerfile with one Swift rule, a finding at every function.
struct SwiftRules: Dangerfile {
    static var rules: [Rule] {
        Rule.swiftSource("Functions") { file in
            file.functions.map { .message($0.name, at: $0.location) }
        }
    }
}

/// The two ways a reading and its time limit can race.
@Suite("A reading's time limit")
struct LargeStackHopTests {
    @Test("a limit that runs out first abandons the reading, which never starts its use and ends its runaway")
    func limitFirst() async throws {
        let gate = ParseGate()
        let release = DispatchSemaphore(value: 0)
        let used = Mutex(false)
        let value = await LargeStack.value(timeLimit: .milliseconds(20), gate: gate) {
            release.wait()
            return 1
        } then: { read in
            used.withLock { $0 = true }
            return read
        }
        #expect(value == nil)
        #expect(!gate.isOpen)
        release.signal()
        try await SwiftSourceRuleTests.waitUntilOpen(gate)
        #expect(!used.withLock { $0 })
    }

    @Test("a reading that ends first is used, however long its use takes past the limit")
    func readingFirst() async {
        let gate = ParseGate()
        let value = await LargeStack.value(timeLimit: .milliseconds(20), gate: gate) {
            1
        } then: { read in
            Thread.sleep(forTimeInterval: 0.2)
            return read + 1
        }
        #expect(value == 2)
        #expect(gate.isOpen)
    }
}
