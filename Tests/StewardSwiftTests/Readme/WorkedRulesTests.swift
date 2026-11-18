@testable import ReadmeDangerfile
import StewardSwift
import StewardTesting
import Testing

/// The README's worked rules, each run on a pull request that creates a
/// file with what it looks for, and what it should let pass.
@Suite("The README: worked rules")
struct WorkedRulesTests {
    /// The findings `rule` makes on a pull request that creates `path`.
    static func findings(_ rule: Rule, _ path: String, _ source: String) async throws -> [Finding] {
        try await rule.evaluate(try SourceChange.context(from: [:], to: [path: source]))
    }

    @Test("a function that returns LoadResult is async")
    func asyncLoaders() async throws {
        let source = """
            struct FeedLoader {
                func load() -> LoadResult { .empty }
                func reload() async -> LoadResult { .empty }
            }

            """
        #expect(try await Self.findings(Checks.asyncLoaders, "Sources/FeedLoader.swift", source) == [
            .failure("`load` returns `LoadResult`, so it's `async`.",
                     at: Location(path: "Sources/FeedLoader.swift", line: 2)),
        ])
    }

    @Test("private members come last in their type or extension")
    func privateLast() async throws {
        let source = """
            struct Feed {
                private var cache: [Item] = []
                func refresh() {}
                private func merge() {}
            }

            extension Feed {
                func clear() {}
            }

            """
        #expect(try await Self.findings(Checks.privateLast, "Sources/Feed.swift", source) == [
            .warning("`refresh` follows a private member.", at: Location(path: "Sources/Feed.swift", line: 3)),
        ])
    }

    @Test("a class is final unless it's open")
    func finalClasses() async throws {
        let source = """
            class Cache {}
            final class Store {}
            open class Base {}
            struct Value {}

            """
        #expect(try await Self.findings(Checks.finalClasses, "Sources/Cache.swift", source) == [
            .warning("Class `Cache` isn't `final`.", at: Location(path: "Sources/Cache.swift", line: 1)),
        ])
    }

    @Test("a public struct has a public initializer")
    func publicInitializers() async throws {
        let source = """
            public struct Item {
                public var name: String
            }

            public struct Tag {
                public var name: String
                public init(name: String) { self.name = name }
            }

            struct Internal {}

            """
        #expect(try await Self.findings(Checks.publicInitializers, "Sources/Item.swift", source) == [
            .warning("Public struct `Item` has no public initializer.",
                     at: Location(path: "Sources/Item.swift", line: 1)),
        ])
    }

    @Test("no @testable import outside Tests/")
    func testableImports() async throws {
        let source = "import Foundation\n@testable import FeedKit\n"
        #expect(try await Self.findings(Checks.testableImports, "Sources/App/App.swift", source) == [
            .failure("`@testable import FeedKit` is for tests.", at: Location(path: "Sources/App/App.swift", line: 2)),
        ])
        #expect(try await Self.findings(Checks.testableImports, "Tests/AppTests/AppTests.swift", source).isEmpty)
    }

    @Test("a Bool parameter is a flag")
    func flagParameters() async throws {
        let source = "func load(force: Bool, from url: URL) {}\n"
        #expect(try await Self.findings(Checks.flagParameters, "Sources/Loader.swift", source) == [
            .message("`force` is a `Bool` flag.", at: Location(path: "Sources/Loader.swift", line: 1)),
        ])
    }

    @Test("a public function has a doc comment")
    func documentedPublicAPI() async throws {
        let source = """
            /// Loads the feed.
            public func load() {}

            @discardableResult
            public func reload() -> Bool { true }

            func helper() {}

            """
        #expect(try await Self.findings(Checks.documentedPublicAPI, "Sources/Feed.swift", source) == [
            .warning("Public function `reload` has no doc comment.", at: Location(path: "Sources/Feed.swift", line: 5)),
        ])
    }
}
