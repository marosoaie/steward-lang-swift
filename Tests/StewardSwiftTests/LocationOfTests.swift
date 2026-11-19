import StewardSwift
import Testing

/// `SwiftFile.location(of:)`, for a finding at a raw node.
@Suite("A node's location")
struct LocationOfTests {
    /// The tokens of `file` whose text is `text`.
    static func tokens(_ text: String, in file: SwiftFile) -> [TokenSyntax] {
        file.syntax.tokens(viewMode: .sourceAccurate).filter { $0.text == text }
    }

    @Test("a node's location is its first token's line, as git counts lines")
    func lines() async throws {
        let file = try await Sample.file("let a = 1\n\n/// Doc.\nfunc f() {\n    print(\"a\" +\n        \"b\")\n}\n")
        #expect(Self.tokens("+", in: file).map { file.location(of: $0) } == [Location(path: Sample.path, line: 5)])
        let function = try #require(file.syntax.tokens(viewMode: .sourceAccurate).first { $0.text == "func" }?.parent)
        // The doc comment is trivia: the node starts at its first token.
        #expect(file.location(of: function) == Location(path: Sample.path, line: 4))
    }

    @Test("a lone carriage return isn't a line break, and #sourceLocation doesn't move a line")
    func hostile() async throws {
        let file = try await Sample.file("""
            #sourceLocation(file: "x", line: 9223372036854775807)
            let a = 1\rlet b = "x" + "y"
            #sourceLocation()
            let c = 2

            """)
        #expect(Self.tokens("+", in: file).map { file.location(of: $0).line } == [2])
        #expect(Self.tokens("c", in: file).map { file.location(of: $0).line } == [4])
    }
}
