import Foundation
@testable import ReadmeDangerfile
import StewardSwift
import StewardTesting
import Testing

/// README.md against what the tests compile and run: its Swift blocks are
/// the examples word for word, and what it says they report is what they
/// report.
@Suite("The README", .timeLimit(.minutes(5)))
struct ReadmeTests {
    /// The pull request the README's first example comments on.
    static let feedBase = ["Sources/Feed/FeedLoader.swift": """
        struct FeedLoader {
            func cached() -> LoadResult { .empty }
        }

        """]
    static let feedHead = ["Sources/Feed/FeedLoader.swift": """
        struct FeedLoader {
            func cached() -> LoadResult { .empty }

            func load(from url: URL) -> LoadResult {
                .empty
            }
        }

        """]

    /// The pull request the README shows the scopes on.
    static let scopesBase = ["Sources/Feed/Feed.swift": """
        struct Feed {
            func refresh() {}

            func clear() {}
        }

        struct Cache {
            private func evict() {}

            func store() {}
        }

        """]
    static let scopesHead = ["Sources/Feed/Feed.swift": """
        struct Feed {
            func refresh() {}

            private func reload() {}

            func clear() {}
        }

        struct Cache {
            private func evict() {}

            func store() {}
        }

        """]

    @Test("every Swift block in the README is a compiled example, word for word, and every example is in it")
    func examples() throws {
        // The manifest and the scopes' file are checked by their own tests.
        try Self.expectExamples(in: Document(Document.readme), except: ["manifest", "scopes-file"])
    }

    /// Each Swift block in `document`, but those named in `exceptions`, is
    /// the example its marker names, word for word; and each example is
    /// one of its blocks.
    static func expectExamples(in document: Document, except exceptions: Set<String> = []) throws {
        let examples = try document.examples()
        let swiftBlocks = document.blocks.filter { block in
            block.language == "swift" && !(block.name.map(exceptions.contains) ?? false)
        }
        #expect(!swiftBlocks.isEmpty)
        swiftBlocks.forEach { block in
            guard let name = block.name else {
                Issue.record("\(document.source.path):\(block.line): a Swift block with no marker before it")
                return
            }
            #expect(
                examples[name] == block.text,
                "\(document.source.path):\(block.line): \(name) differs from its example"
            )
        }
        let shown = Set(swiftBlocks.compactMap(\.name))
        #expect(Set(examples.keys).subtracting(shown).isEmpty, "examples \(document.source.path) doesn't show")
    }

    @Test("every fence in the README is one the checker reads: backticks at the start of a line, a language it knows")
    func fences() throws {
        try Self.expectFences(in: Document(Document.readme))
    }

    /// Every fence in `document` is one the checker reads: backticks at the
    /// start of a line, opening a block in a language the tests know.
    static func expectFences(in document: Document) throws {
        let fences = document.text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
        }
        #expect(fences.allSatisfy { $0.hasPrefix("```") }, "\(document.source.path): \(fences)")
        #expect(fences.count == 2 * document.blocks.count, "\(document.source.path)")
        #expect(Set(document.blocks.map(\.language)).isSubset(of: ["swift", "yaml", "diff", "sh"]))
    }

    @Test("the comment the README shows is the one its Dangerfile leaves on its pull request")
    func comment() throws {
        let repository = try TestRepository()
        defer { repository.remove() }
        try repository.commit(Self.feedBase, message: "Base")
        try repository.git(["checkout", "--quiet", "-b", "feature"])
        try repository.commit(Self.feedHead, message: "Load feeds")
        let run = try Subprocess.run(
            try SwiftSourceEndToEndTests.executable("ReadmeDangerfile"),
            ["--base", "main"],
            environment: Subprocess.environment(),
            in: repository.url
        )
        #expect(run.status == 1, "\(run.error)")
        // The log line the README quotes, from this run.
        let checking = "Async loaders: checking Sources/Feed/FeedLoader.swift"
        #expect(run.error.contains(checking + "\n"), "\(run.error)")
        #expect(try Document(Document.readme).text.contains(checking))
        // The summary, less the footer, which a comment in CI has its own of.
        let printed = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .prefix { !$0.hasPrefix("<sub>") }
        let shown = try Document(Document.readme).section("comment").filter { !$0.isEmpty }
            .map { $0 == ">" ? "" : String($0.dropFirst(2)) }
        let sha = try #require(shown.first?.split(separator: " ").last)
        let expected = printed.map { $0.replacing(/on [0-9a-f]{7}$/, with: "on \(sha)") }
        #expect(Array(expected.drop { $0.isEmpty }.reversed().drop { $0.isEmpty }.reversed()) == shown)
    }

    @Test("the scopes act as the README shows, on the diff it shows")
    func scopes() async throws {
        let repository = try TestRepository()
        defer { repository.remove() }
        let base = try repository.commit(Self.scopesBase, message: "Base")
        let head = try repository.commit(Self.scopesHead, message: "Head")
        let diff = try repository.diff(from: base, to: head)
        let readme = try Document(Document.readme)
        #expect(try readme.block("scopes-diff").text + "\n" == diff, "\(diff)")
        #expect(try readme.block("scopes-file").text + "\n" == Self.scopesHead["Sources/Feed/Feed.swift"])
        let context = try Context.fixture(diff: diff, files: Self.scopesHead)
        for scope in SwiftSourceScope.allCases {
            // README's privateLast, in each scope, naming what it reports.
            let rule = Rule.swiftSource(Checks.privateLast.name, reporting: scope) { file in
                file.memberBlocks.flatMap { block in
                    block.members.drop { $0.access.level != .private }.filter { $0.access.level != .private }
                        .map { .warning($0.name, at: $0.location) }
                }
            }
            let names = try await rule.evaluate(context).map { "`\($0.text)`" }
            let row = "| `.\(scope)` | \(names.isEmpty ? "nothing" : names.joined(separator: ", ")) |"
            #expect(readme.text.contains(row), "README.md has no row \(row)")
        }
    }

    @Test("what the README says a skip, a damaged file and a refusal read like is what the rule reports")
    func skips() async throws {
        let context = try SourceChange.context(from: [:], to: [
            "Sources/Feed/Draft.swift": "func draft( {\n",
            "Sources/Feed/Matrix.swift": "let x = " + String(repeating: "[", count: 22) + "1"
                + String(repeating: "]", count: 22) + "\n",
        ])
        // As a run has them, with its log.
        let outcome = await Checks.run(on: context)
        let findings = outcome.report?.findings ?? []
        #expect(findings.count == 2)
        let readme = try Document(Document.readme)
        findings.forEach { finding in
            #expect(readme.text.contains(finding.text), "README.md doesn't quote \(finding.text)")
        }
        let skipped = "Async loaders: skipped Sources/Feed/Draft.swift, with syntax errors"
        #expect(outcome.log.contains(skipped + "\n"), "\(outcome.log)")
        #expect(readme.text.contains(skipped))
    }

    @Test("the README's manifest asks for the Steward this package builds against, and SwiftPM reads it")
    func manifest() throws {
        let manifest = try Document(Document.readme).block("manifest").text
        let own = try String(contentsOf: Document.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let steward = try #require(own.split(separator: "\n").first { $0.contains("swift-steward.git") })
        #expect(manifest.contains(steward.trimmingCharacters(in: .whitespaces)))
        // The prose's versions: swift-syntax's range and Steward's minor
        // release, as Package.swift has them.
        let readme = try Document(Document.readme).text
        let range = try #require(own.firstMatch(of: /swift-syntax\.git", "([0-9.]+)"\.\.<"([0-9.]+)"/))
        #expect(readme.contains("`\(range.1)`") && readme.contains("`\(range.2)`"))
        let minor = try #require(steward.firstMatch(of: /from: "([0-9]+\.[0-9]+)\.0"/))
        #expect(readme.contains("(\(minor.1) for now)"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("steward-lang-swift-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: directory.appendingPathComponent("Package.swift"))
        let run = try Subprocess.run(
            URL(fileURLWithPath: "/usr/bin/env"),
            ["swift", "package", "dump-package"],
            environment: Subprocess.environment(),
            in: directory
        )
        #expect(run.status == 0, "\(run.error)")
        #expect(run.output.contains("\"steward-lang-swift\""), "\(run.output)")
    }

    @Test("the README's workflow pins steward-action exactly and limits the job's time")
    func workflow() throws {
        let workflow = try Document(Document.readme).block("workflow").text
        #expect(workflow.contains("uses: marosoaie/steward-action@v0.1.1"))
        #expect(workflow.contains("timeout-minutes:"))
    }
}
