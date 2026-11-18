import Foundation
import Testing

/// SwiftRulesFixture run as its own process, as a workflow runs a
/// Dangerfile: a dry run (`--base main`) in a git repository whose
/// checked-out branch is the pull request's head.
@Suite("A Dangerfile with Swift rules, end to end", .timeLimit(.minutes(5)))
struct SwiftSourceEndToEndTests {
    static let base = [
        "Sources/Loader.swift": """
            struct Loader {
                func old() -> LoadResult { .empty }

                func keep() {}
            }

            """,
    ]

    /// Adds a private function above `keep` and a new loader that isn't
    /// `async`, and a file with syntax errors.
    static let head = [
        "Sources/Loader.swift": """
            struct Loader {
                func old() -> LoadResult { .empty }

                private func helper() {}

                func keep() {}

                func load() -> LoadResult { .empty }
            }

            """,
        "Sources/Broken.swift": "func broken( {\n",
    ]

    /// The rules' names, which start each line they write.
    static let rules = ["Async loaders", "Private last", "Crash marker"]

    @Test("a dry run reports the findings in what changed, skips the broken file, and fails the job")
    func run() throws {
        let run = try Self.run(from: Self.base, to: Self.head)
        #expect(run.reason == .exit)
        #expect(run.status == 1, "\(run.error)")
        // The loader that didn't change isn't reported; the members a new
        // private one misplaces are, under changedTypes.
        #expect(run.output.contains("`load` returns `LoadResult`, so it's `async`.<br>`Sources/Loader.swift:8`"),
                "\(run.output)")
        #expect(!run.output.contains("`old`"), "\(run.output)")
        #expect(run.output.contains("`keep` follows a private member.<br>`Sources/Loader.swift:6`"), "\(run.output)")
        #expect(run.output.contains("`load` follows a private member.<br>`Sources/Loader.swift:8`"), "\(run.output)")
        #expect(run.output.contains("Rule “Async loaders” skipped `Sources/Broken.swift`, with syntax errors."),
                "\(run.output)")
        #expect(run.error.contains("""
            Async loaders: checking Sources/Broken.swift
            Async loaders: skipped Sources/Broken.swift, with syntax errors
            Async loaders: checking Sources/Loader.swift

            """), "\(run.error)")
    }

    @Test("a check that crashes fails the job, prints no summary, and the last line a rule logged names the file")
    func crash() throws {
        var head = Self.head
        head["Sources/Crash.swift"] = "// steward-swift-fixture: crash\nfunc crash() {}\n"
        head["Sources/Later.swift"] = "func later() {}\n"
        let run = try Self.run(from: Self.base, to: head)
        #expect(run.reason == .uncaughtSignal, "status \(run.status), \(run.error)")
        #expect(run.output.isEmpty, "\(run.output)")
        let lines = run.error.split(separator: "\n").map(String.init)
        let ruleLines = lines.filter { line in Self.rules.contains { line.hasPrefix("\($0): ") } }
        #expect(ruleLines.last == "Crash marker: checking Sources/Crash.swift", "\(run.error)")
        // What follows it is the Swift runtime's report of the crash.
        let after = lines.drop { $0 != "Crash marker: checking Sources/Crash.swift" }.dropFirst()
        #expect(after.contains { $0.contains("Fatal error: the crash marker") }, "\(run.error)")
    }

    /// SwiftRulesFixture's dry run on a pull request from `base`'s files to
    /// `head`'s, the head checked out on a branch off `main`.
    static func run(from base: [String: String], to head: [String: String]) throws -> Subprocess {
        let repository = try TestRepository()
        defer { repository.remove() }
        try repository.commit(base, message: "Base")
        try repository.git(["checkout", "--quiet", "-b", "feature"])
        try repository.commit(head, message: "Head")
        // No backtrace: the crash's report is the runtime's one line.
        let environment = Subprocess.environment(adding: ["SWIFT_BACKTRACE": "enable=no"])
        return try Subprocess.run(
            try Self.executable("SwiftRulesFixture"), ["--base", "main"], environment: environment, in: repository.url
        )
    }

    /// The executable `name` the test build puts beside the tests: on
    /// macOS, `swift test` and Xcode put the tests' `.xctest` bundle there,
    /// and on Linux the tests are an executable there.
    static func executable(_ name: String) throws -> URL {
        let directories = [
            Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent(),
            URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent(),
            Bundle.main.bundleURL,
        ]
        let found = directories.map { $0.appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let found else {
            throw SubprocessError("\(name) wasn't built beside the tests in \(directories.map(\.path))")
        }
        return found
    }
}

/// A class of the tests' own, whose bundle is the tests'.
private final class BundleMarker {}
