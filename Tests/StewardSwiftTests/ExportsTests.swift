// Only StewardSwift, which re-exports Steward, GitDiffKit,
// PullRequestHosting and SwiftSyntax: this file compiles only if one
// import serves a Dangerfile's Swift rules.
import StewardSwift
import Testing

@Suite("One import")
struct ExportsTests {
    @Test("a file that imports only StewardSwift writes a rule and reads every name it needs")
    func oneImport() throws {
        let rule: Rule = Rule.swiftSource("Functions", in: PathPattern("Sources/**")) { file in
            file.functions.map { Finding.message($0.name, at: $0.location) }
        }
        let location: Steward.Location = try SwiftFile(source: "func a() {}\n", path: "A.swift").functions[0].location
        let lines: LineRangeSet = LineRangeSet([1...2])
        let node: SourceFileSyntax? = nil
        #expect(rule.name == "Functions")
        #expect(location.line == 1)
        #expect(lines.overlaps(2...3))
        #expect(node == nil)
    }
}
