import StewardSwift
import StewardTesting
import SwiftParser
import Testing

// This file doesn't import SwiftSyntax: its syntax types reach it only
// through StewardSwift's re-export, so it builds only while that holds.

@Suite("The dependency graph")
struct DependencyGraphTests {
    @Test("a source parsed with SwiftParser reads through StewardSwift's re-export of SwiftSyntax")
    func parseThroughReExport() {
        let functions = Parser.parse(source: LoaderSample.source).functions
        #expect(functions.map(\.name.text) == ["load", "reload"])
        #expect(functions.map(\.isAsync) == [false, true])
    }

    @Test("a Steward rule on a fixture context reports a parsed declaration at its line")
    func ruleOnFixtureContext() async throws {
        let context = try Context.fixture(diff: LoaderSample.diff)
        let findings = try await Self.asyncLoaders.evaluate(context)
        #expect(findings == [
            .failure(
                "`load` returns `LoadResult`, so it should be `async`.",
                at: Location(path: LoaderSample.path, line: 3)
            ),
        ])
    }

    /// The rule that started the package, over the created files. Steward
    /// 0.2 can't read a file's contents, so the sample stands in for them.
    static let asyncLoaders = Rule("Async loaders") { context in
        context.git.createdFiles.flatMap { path in
            let tree = Parser.parse(source: LoaderSample.source)
            let converter = SourceLocationConverter(fileName: path, tree: tree)
            return tree.functions
                .filter { $0.signature.returnClause?.type.trimmedDescription == "LoadResult" && !$0.isAsync }
                .map { function in
                    Finding.failure(
                        "\(Markdown.codeSpan(function.name.text)) returns `LoadResult`, so it should be `async`.",
                        at: Location(path: path, line: function.startLocation(converter: converter).line)
                    )
                }
        }
    }
}

/// A file that a pull request creates, and the pull request's diff.
private enum LoaderSample {
    static let path = "Sources/App/Loader.swift"

    static let source = """
        import Foundation

        func load() -> LoadResult { .empty }

        func reload() async -> LoadResult { .empty }
        """

    /// The diff that creates `path` with `source`, as git writes it.
    static var diff: String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        return """
            diff --git a/\(path) b/\(path)
            new file mode 100644
            index 0000000..1111111
            --- /dev/null
            +++ b/\(path)
            @@ -0,0 +1,\(lines.count) @@
            \(lines.map { "+\($0)" }.joined(separator: "\n"))

            """
    }
}

extension SourceFileSyntax {
    /// The file's top-level functions.
    fileprivate var functions: [FunctionDeclSyntax] {
        statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
    }
}

extension FunctionDeclSyntax {
    fileprivate var isAsync: Bool {
        signature.effectSpecifiers?.asyncSpecifier != nil
    }
}
