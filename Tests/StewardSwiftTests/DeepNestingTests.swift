import StewardSwift
import StewardTesting
import Testing

/// Source nested far deeper than real code, read from `async` code, as a
/// Dangerfile's rules are: on macOS its threads have 512 KiB stacks, which
/// swift-syntax's parser overflows at a few hundred levels.
@Suite("Deep nesting", .timeLimit(.minutes(5)))
struct DeepNestingTests {
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

    @Test("a shape nested 20,000 deep reads without trapping, from async code", arguments: Shape.allCases)
    func deep(shape: Shape) async {
        let source = shape.source(depth: 20_000)
        let file = await Task.detached { SwiftFile(source: source, path: "Deep.swift") }.value
        Invariants.check(file, source: source)
    }

    @Test("functions nested past the parser's limit are read down to it")
    func functionsPastTheLimit() async {
        let source = Shape.functions.source(depth: 1_000)
        let file = await Task.detached { SwiftFile(source: source, path: "Deep.swift") }.value
        #expect(file.syntax.hasError)
        #expect(file.functions.count > 100)
        #expect(file.functions.map(\.location.line) == Array(1...file.functions.count))
    }
}
