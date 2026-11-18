@testable import StewardSwift
import Testing

@Suite("Nesting scan")
struct NestingScanTests {
    typealias Excess = NestingScan.Excess

    static func nested(_ open: String, _ close: String, depth: Int, inner: String = "a") -> String {
        String(repeating: open, count: depth) + inner + String(repeating: close, count: depth)
    }

    static let excessCases: [(String, Excess)] = [
        ("let x = " + nested("[", "]", depth: 25), Excess(shape: .squareBrackets, line: 1)),
        ("let x: " + nested("A<", ">", depth: 513, inner: "B"), Excess(shape: .angleBrackets, line: 1)),
        ("let x: " + nested("A<\n", ">", depth: 513, inner: "B"), Excess(shape: .angleBrackets, line: 513)),
        ("let x = " + String(repeating: "a < ", count: 513) + "b", Excess(shape: .angleBrackets, line: 1)),
        (nested("#if A\n", "#endif\n", depth: 513, inner: ""), Excess(shape: .conditionalCompilation, line: 513)),
        ("let x = " + nested("\"\\(", ")\"", depth: 513), Excess(shape: .interpolation, line: 1)),
        ("let x = " + nested("#\"\\#(", ")\"#", depth: 513), Excess(shape: .interpolation, line: 1)),
    ]

    static let withinLimitCases: [String] = [
        "let x = " + nested("[", "]", depth: 20),
        "let x: " + nested("A<", ">", depth: 512, inner: "B"),
        nested("#if A\n", "#endif\n", depth: 512, inner: ""),
        "let x = " + nested("\"\\(", ")\"", depth: 512),
    ]

    static let commentAndStringCases: [String] = [
        "// " + nested("[", "]", depth: 40),
        "/* " + nested("[", "]", depth: 40) + " /* nested */ still a comment */",
        "let s = \"" + String(repeating: "[", count: 40) + "\"",
        "let s = \"\"\"\n" + String(repeating: "[<", count: 600) + "\n\"\"\"",
        "let s = #\"" + String(repeating: "[\\(", count: 600) + "\"#",
        "let s = \"#if A\"\n" + String(repeating: "let t = \"#if A\"\n", count: 600),
        "let s = \"\\\"" + String(repeating: "[", count: 40) + "\"",
    ]

    static let comparisonCases: [String] = [
        String(repeating: "if a < b { c() }\n", count: 600),
        String(repeating: "x = a < b; ", count: 600),
        String(repeating: "let x = a < b\n", count: 600),
        String(repeating: "for i in 0..<n {}\n", count: 600),
        String(repeating: "a <<= 1; b <= c\n", count: 600),
    ]

    @Test("real files pass the scan", .enabled(if: Corpus.isNetworkAllowed))
    func realFiles() async throws {
        let files = try await Corpus.argumentParserFiles() + Corpus.ownFiles
        let excesses = files.compactMap { file in NestingScan.firstExcess(in: file.source).map { (file.path, $0) } }
        #expect(excesses.isEmpty, "\(excesses)")
    }

    @Test(
        "each shape past its limit is found, at the line where it goes past",
        arguments: excessCases
    )
    func excess(source: String, excess: Excess) {
        #expect(NestingScan.firstExcess(in: source) == excess)
    }

    @Test(
        "shapes up to their limits pass",
        arguments: withinLimitCases
    )
    func withinLimits(source: String) {
        #expect(NestingScan.firstExcess(in: source) == nil)
    }

    @Test("nested arrays are budgeted over the whole file")
    func squareBracketBudget() {
        let site = "let x = " + Self.nested("[", "]", depth: 16) + "\n"
        #expect(NestingScan.firstExcess(in: String(repeating: site, count: 30)) == nil)
        #expect(NestingScan.firstExcess(in: String(repeating: site, count: 40))?.shape == .squareBrackets)
    }

    @Test(
        "brackets in comments and string literals don't count",
        arguments: commentAndStringCases
    )
    func commentsAndStrings(source: String) {
        #expect(NestingScan.firstExcess(in: source) == nil)
    }

    @Test(
        "comparisons don't add up past braces, semicolons and assignments",
        arguments: comparisonCases
    )
    func comparisons(source: String) {
        #expect(NestingScan.firstExcess(in: source) == nil)
    }

    @Test("an unterminated string ends at its line, as the parser recovers")
    func unterminatedString() {
        let source = "let s = \"open\n" + "let x = " + Self.nested("[", "]", depth: 25)
        #expect(NestingScan.firstExcess(in: source) == Excess(shape: .squareBrackets, line: 2))
    }

    @Test(
        "the scan takes linear time on input made of what it looks at",
        .timeLimit(.minutes(1)),
        arguments: ["#", "\"", "/*", "\\(", "<", "[]", "\"\\(", "#\"", "\n#if A"]
    )
    func linear(unit: String) {
        let source = String(repeating: unit, count: 1_000_000 / unit.utf8.count)
        let elapsed = ContinuousClock().measure { _ = NestingScan.firstExcess(in: source) }
        #expect(elapsed < .seconds(5), "a megabyte of \(unit.debugDescription) took \(elapsed)")
    }
}
