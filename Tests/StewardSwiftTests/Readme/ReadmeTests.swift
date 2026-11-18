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
        let readme = try Readme()
        let examples = try Readme.examples()
        // The manifest and the scopes' file are checked by their own tests.
        let swiftBlocks = readme.blocks.filter { block in
            block.language == "swift" && !["manifest", "scopes-file"].contains(block.name)
        }
        #expect(!swiftBlocks.isEmpty)
        swiftBlocks.forEach { block in
            guard let name = block.name else {
                Issue.record("README.md:\(block.line): a Swift block with no `<!-- README: name -->` before it")
                return
            }
            #expect(examples[name] == block.text, "README.md:\(block.line): \(name) differs from its example")
        }
        let shown = Set(swiftBlocks.compactMap(\.name))
        #expect(Set(examples.keys).subtracting(shown).isEmpty, "examples the README doesn't show")
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
        // The summary, less the footer, which a comment in CI has its own of.
        let printed = run.output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .prefix { !$0.hasPrefix("<sub>") }
        let shown = try Readme().section("comment").filter { !$0.isEmpty }
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
        let readme = try Readme()
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
        let findings = try await Checks.asyncLoaders.evaluate(context)
        #expect(findings.count == 2)
        let readme = try Readme()
        findings.forEach { finding in
            #expect(readme.text.contains(finding.text), "README.md doesn't quote \(finding.text)")
        }
        #expect(readme.text.contains("Async loaders: skipped Sources/Feed/Draft.swift, with syntax errors"))
    }

    @Test("the README's manifest asks for the Steward this package builds against, and SwiftPM reads it")
    func manifest() throws {
        let manifest = try Readme().block("manifest").text
        let own = try String(contentsOf: Readme.root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let steward = try #require(own.split(separator: "\n").first { $0.contains("swift-steward.git") })
        #expect(manifest.contains(steward.trimmingCharacters(in: .whitespaces)))
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
        let workflow = try Readme().block("workflow").text
        #expect(workflow.contains("uses: marosoaie/steward-action@v0.1.1"))
        #expect(workflow.contains("timeout-minutes:"))
    }
}
