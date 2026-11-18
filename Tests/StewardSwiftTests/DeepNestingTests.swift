@testable import StewardSwift
import StewardTesting
import Testing

/// Source nested far deeper than real code, read from `async` code, as a
/// Dangerfile's rules are: on macOS its threads have 512 KiB stacks, which
/// swift-syntax's parser overflows at a few hundred levels.
@Suite("Deep nesting", .timeLimit(.minutes(5)))
struct DeepNestingTests {
    /// Reads `source` with a gate of its own and a generous time limit:
    /// these tests check that nothing traps, not how long a parse takes on
    /// a busy machine, and a runaway here mustn't refuse other tests' files.
    static func read(_ source: String) throws(SwiftFile.Refusal) -> SwiftFile {
        try SwiftFile.read(source: source, path: "Deep.swift", timeLimit: .seconds(120), gate: ParseGate())
    }

    /// A shape, repeated `depth` times inside itself.
    enum Shape: String, CaseIterable, Sendable {
        case parentheses, braces, functions, types, postfixChain, optionals, memberAccess
        case unclosedParentheses, unclosedBraces, binaryOperators

        func source(depth: Int) -> String {
            switch self {
            case .parentheses: "let x = " + nested("(", "a", ")", depth)
            case .braces: "let x = " + nested("{ ", "a", " }", depth)
            case .functions: nested("func f() {\n", "", "}\n", depth)
            case .types: nested("struct S {\n", "func f() {}\n", "}\n", depth)
            case .postfixChain: "let x = a" + String(repeating: ".b()", count: depth)
            case .optionals: "let x: Int" + String(repeating: "?", count: depth)
            case .memberAccess: "let x = a" + String(repeating: ".b", count: depth)
            case .unclosedParentheses: "let x = " + String(repeating: "(", count: depth)
            case .unclosedBraces: "let x = " + String(repeating: "{", count: depth)
            case .binaryOperators: "let x = " + Array(repeating: "a", count: depth).joined(separator: " + ")
            }
        }

        private func nested(_ open: String, _ inner: String, _ close: String, _ depth: Int) -> String {
            String(repeating: open, count: depth) + inner + String(repeating: close, count: depth)
        }
    }

    @Test(
        "a shape nested 20,000 deep is read or refused, never trapping, from async code",
        arguments: Shape.allCases
    )
    func deep(shape: Shape) async {
        let source = shape.source(depth: 20_000)
        let outcome = await Task.detached {
            Result { () throws(SwiftFile.Refusal) in try Self.read(source) }
        }.value
        switch outcome {
        case .success(let file):
            Invariants.check(file, source: source)
        case .failure(.syntaxTreeTooDeep(let depth, let limit)):
            #expect(depth > limit)
        case .failure(.nestedPastParserLimit(let limit)):
            #expect(limit == 256)
        case .failure(let refusal):
            Issue.record("\(shape) was refused before parsing: \(refusal)")
        }
    }

    @Test("source nested past the parser's limit is refused, so nothing after it is lost")
    func pastTheParserLimit() throws {
        // Past its limit the parser leaves the rest of the file as
        // unexpected text, so `hidden` would be missing from the model.
        let source = Shape.functions.source(depth: 300) + "func hidden() {}\n"
        #expect(throws: SwiftFile.Refusal.nestedPastParserLimit(limit: 256)) { try Self.read(source) }
        let shown = try Self.read(Shape.functions.source(depth: 60) + "func shown() {}\n")
        #expect(shown.functions.last?.name == "shown")
    }

    @Test("a tree at the depth limit can be walked by a recursive visitor on a 512 KiB stack")
    func visitorAtTheLimit() throws {
        // `let x = a` and n calls make a tree 2n + 9 levels deep, so this is
        // the longest chain the limit lets through. Raise the limit past
        // what the visitor survives, and this test crashes.
        let calls = (SwiftFile.maximumTreeDepth - 9) / 2
        let file = try Self.read(Shape.postfixChain.source(depth: calls))
        #expect(file.syntax.depth(cappedAt: .max) > SwiftFile.maximumTreeDepth - 3)
        let walked = LargeStack.runOnSmallStack { NodeCounter.count(file.syntax) }
        #expect(walked ?? 0 > calls * 4)
        #expect(throws: SwiftFile.Refusal.self) { try Self.read(Shape.postfixChain.source(depth: calls + 2)) }
    }

    @Test("a tree deeper than rules can walk is refused, and one within the limit is read")
    func treeDepth() throws {
        let refusal = #expect(throws: SwiftFile.Refusal.self) {
            try Self.read(Shape.postfixChain.source(depth: 2_000))
        }
        if case .syntaxTreeTooDeep(let depth, let limit)? = refusal {
            #expect(depth > limit && limit == 512)
        } else {
            Issue.record("expected syntaxTreeTooDeep, got \(String(describing: refusal))")
        }
        _ = try Self.read(Shape.postfixChain.source(depth: 200))
    }
}
