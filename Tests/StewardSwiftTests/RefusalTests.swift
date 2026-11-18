@testable import StewardSwift
import Testing

@Suite("Refusals")
struct RefusalTests {
    typealias Refusal = SwiftFile.Refusal

    static func nested(_ open: String, _ close: String, depth: Int, inner: String) -> String {
        String(repeating: open, count: depth) + inner + String(repeating: close, count: depth)
    }

    static let shapes: [(String, Refusal)] = [
        (
            "let a = 1\nlet x = " + nested("[", "]", depth: 22, inner: "1"),
            .nestingTooDeep(.squareBrackets, line: 2, limit: 1 << 22)
        ),
        ("let x: " + nested("A<", ">", depth: 600, inner: "B"), .nestingTooDeep(.angleBrackets, line: 1, limit: 512)),
        (
            nested("#if A\n", "#endif\n", depth: 600, inner: ""),
            .nestingTooDeep(.conditionalCompilation, line: 513, limit: 512)
        ),
        (
            nested("/**/#if A\n", "#endif\n", depth: 600, inner: ""),
            .nestingTooDeep(.conditionalCompilation, line: 513, limit: 512)
        ),
        (
            "let x = " + nested("\"\\(", ")\"", depth: 600, inner: "1"),
            .nestingTooDeep(.interpolation, line: 1, limit: 512)
        ),
    ]

    @Test("a shape nested past its limit is refused before parsing, with its line and limit", arguments: shapes)
    func nestingTooDeep(source: String, refusal: Refusal) {
        #expect(throws: refusal) { try SwiftFile(source: source, path: "Sources/Deep.swift") }
    }

    @Test("source with syntax errors isn't refused: it's read, and says so")
    func syntaxErrorsAreRead() throws {
        let file = try SwiftFile(source: "func load( {\nfunc after() {}", path: "Sources/Broken.swift")
        #expect(file.syntax.hasError)
        #expect(file.functions.map(\.name).contains("after"))
    }

    @Test("the time limit is two seconds and 50 µs a byte")
    func timeLimit() {
        #expect(SwiftFile.timeLimit(forUTF8Count: 0) == .seconds(2))
        #expect(SwiftFile.timeLimit(forUTF8Count: 1_000_000) == .seconds(52))
        #expect(SwiftFile.timeLimit(forUTF8Count: .max) > .seconds(52))
    }

    @Test(
        "a parse that runs out of time is refused, and no other starts until it ends",
        .timeLimit(.minutes(2))
    )
    func timeOutAndRunaway() async throws {
        // About a megabyte of ordinary code: a second or two to parse in a
        // debug build, far more than a millisecond.
        let slow = String(repeating: "let value = first + second * third - fourth\n", count: 24_000)
        let gate = ParseGate()
        #expect(throws: Refusal.timedOut(limit: .milliseconds(1))) {
            try SwiftFile.read(source: slow, path: "Slow.swift", timeLimit: .milliseconds(1), gate: gate)
        }
        #expect(!gate.isOpen)
        #expect(throws: Refusal.earlierParseStillRunning) {
            try SwiftFile.read(source: "func f() {}", path: "Next.swift", timeLimit: .seconds(10), gate: gate)
        }
        // The runaway ends on its own, and the gate opens again.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(90)
        while !gate.isOpen, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(gate.isOpen)
        let file = try SwiftFile.read(source: "func f() {}", path: "Next.swift", timeLimit: .seconds(10), gate: gate)
        #expect(file.functions.map(\.name) == ["f"])
    }

    @Test(
        "a refusal says what to change",
        arguments: [
            (Refusal.nestingTooDeep(.squareBrackets, line: 7, limit: 1 << 22), "Line 7 nests `[` too deeply"),
            (.nestingTooDeep(.angleBrackets, line: 3, limit: 512), "Line 3 goes past 512 unclosed `<`"),
            (.syntaxTreeTooDeep(depth: 600, limit: 512), "600 levels deep, past the 512"),
            (.nestedPastParserLimit(limit: 256), "more than 256 levels deep"),
            (.timedOut(limit: .seconds(52)), "didn't finish within 52 s"),
            (.earlierParseStillRunning, "An earlier file's parse ran out of time"),
        ]
    )
    func descriptions(refusal: Refusal, text: String) {
        #expect(refusal.description.contains(text), "\(refusal.description)")
    }
}
