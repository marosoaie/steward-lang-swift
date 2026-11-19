@testable import Dangerfile
import StewardTesting
import Testing

/// Each of AGENTS.md's conventions as a rule, on a pull request that
/// creates a file breaking it and a file keeping it.
@Suite("The repository's own rules")
struct RecipesTests {
    /// What `rule` finds on a pull request that creates `path`.
    static func findings(_ rule: Rule, _ path: String, _ source: String) async throws -> [Finding] {
        try await rule.evaluate(try PullRequest.creating([path: source]))
    }

    @Test("a class or an actor in Sources/ needs a doc comment that says why it isn't a value type")
    func valueTypes() async throws {
        let source = """
            final class Cache {}

            /// A class, since every reader shares one.
            final class Gate {}

            actor Loader {}

            struct Value {}

            """
        #expect(try await Self.findings(Checks.valueTypes, "Sources/App/Cache.swift", source) == [
            .warning("`Cache` isn't a value type, and its doc comment doesn't say why.",
                     at: Location(path: "Sources/App/Cache.swift", line: 1)),
            .warning("`Loader` isn't a value type, and its doc comment doesn't say why.",
                     at: Location(path: "Sources/App/Cache.swift", line: 6)),
        ])
        #expect(try await Self.findings(Checks.valueTypes, "Tests/AppTests/Cache.swift", source).isEmpty)
    }

    @Test("a public type or function in Sources/ needs a doc comment")
    func documentedPublicAPI() async throws {
        let source = """
            /// A documented type.
            public struct Documented {
                /// A documented function.
                public func documented() {}

                public func undocumented() {}

                func internalOnly() {}
            }

            public enum Undocumented {}

            """
        #expect(try await Self.findings(Checks.documentedPublicAPI, "Sources/App/API.swift", source) == [
            .warning("Public `Undocumented` has no doc comment.",
                     at: Location(path: "Sources/App/API.swift", line: 11)),
            .warning("Public `undocumented` has no doc comment.", at: Location(path: "Sources/App/API.swift", line: 6)),
        ])
    }

    @Test("a public struct needs a public initializer, unless it holds a syntax node")
    func publicInitializers() async throws {
        let source = """
            public struct Bare {
                public var name: String
            }

            public struct Initialized {
                public init() {}
            }

            public struct Extended {}

            extension Extended {
                public init(name: String) {}
            }

            public struct Node {
                public var syntax: DeclSyntax
            }

            """
        #expect(try await Self.findings(Checks.publicInitializers, "Sources/App/Models.swift", source) == [
            .warning("Public struct `Bare` has no public initializer.",
                     at: Location(path: "Sources/App/Models.swift", line: 1)),
        ])
    }

    @Test("a public initializer removed from an extension is a finding at the struct the pull request left alone")
    func initializerRemovedFromExtension() async throws {
        let base = "public struct Item {}\n\nextension Item {\n    public init() {}\n}\n"
        let head = "public struct Item {}\n\nextension Item {\n    init() {}\n}\n"
        let path = "Sources/App/Item.swift"
        let context = try Context.fixture(
            diff: """
                diff --git a/\(path) b/\(path)
                index 1111111..2222222 100644
                --- a/\(path)
                +++ b/\(path)
                @@ -1,5 +1,5 @@
                 public struct Item {}
                \u{20}
                 extension Item {
                -    public init() {}
                +    init() {}
                 }

                """,
            files: [path: head]
        )
        #expect(base != head)
        #expect(try await Checks.publicInitializers.evaluate(context) == [
            .warning("Public struct `Item` has no public initializer.", at: Location(path: path, line: 1)),
        ])
    }

    @Test("an initializer in one #if branch's struct doesn't excuse the other branch's")
    func conditionalStructs() async throws {
        let source = """
            #if os(macOS)
            public struct Platform {
                public init() {}
            }
            #else
            public struct Platform {}
            #endif

            """
        #expect(try await Self.findings(Checks.publicInitializers, "Sources/App/Platform.swift", source) == [
            .warning("Public struct `Platform` has no public initializer.",
                     at: Location(path: "Sources/App/Platform.swift", line: 6)),
        ])
    }

    @Test("a nested public struct matches its initializers by its name with the types around it")
    func nestedInitializers() async throws {
        let source = """
            public struct Outer {
                public init() {}
                public struct Inner {}
            }

            extension Outer.Inner {
                public init(value: Int) {}
            }

            public struct Other {
                public struct Inner {}
            }

            """
        #expect(try await Self.findings(Checks.publicInitializers, "Sources/App/Nested.swift", source) == [
            .warning("Public struct `Other` has no public initializer.",
                     at: Location(path: "Sources/App/Nested.swift", line: 10)),
            .warning("Public struct `Inner` has no public initializer.",
                     at: Location(path: "Sources/App/Nested.swift", line: 11)),
        ])
    }

    @Test("a test in Tests/ needs a sentence for a name, not a bare @Test or a word")
    func sentenceTestNames() async throws {
        let source = """
            @Test("a sentence names what holds")
            func good() {}

            @Test
            func bare() {}

            @Test("word")
            func word() {}

            @Test("a sentence, with arguments", arguments: [1, 2])
            func parameterized(value: Int) {}

            @Test(#"a "quoted" value is read"#)
            func raw() {}

            @Test(\"""
                a sentence over
                two lines
                \""")
            func multiline() {}

            @Test(.serialized)
            func traitOnly() {}

            """
        #expect(try await Self.findings(Checks.sentenceTestNames, "Tests/AppTests/AppTests.swift", source) == [
            .warning("Test `bare` needs a sentence for a name.",
                     at: Location(path: "Tests/AppTests/AppTests.swift", line: 4)),
            .warning("Test `word` needs a sentence for a name.",
                     at: Location(path: "Tests/AppTests/AppTests.swift", line: 7)),
            .warning("Test `traitOnly` needs a sentence for a name.",
                     at: Location(path: "Tests/AppTests/AppTests.swift", line: 22)),
        ])
    }

    @Test("two string literals joined with + are a finding, and a literal joined to anything else isn't")
    func concatenatedLiterals() async throws {
        let source = """
            let a = "one, " + "two"
            let b = name + "two"
            let c = "one" + name + "two"
            let d = #"raw"# + "plain"
            let e = 1 + 2
            #sourceLocation(file: "x", line: 9223372036854775807)

            let f = "far" + "away"
            #sourceLocation()

            """
        let message = "A multiline string literal reads better than literals joined with `+`."
        #expect(try await Self.findings(Checks.concatenatedLiterals, "Sources/App/Text.swift", source) == [
            .message(message, at: Location(path: "Sources/App/Text.swift", line: 1)),
            .message(message, at: Location(path: "Sources/App/Text.swift", line: 4)),
            // At the line git counts, whatever #sourceLocation says: two
            // lines after a directive at Int.max, SourceLocationConverter
            // overflows and ends the process.
            .message(message, at: Location(path: "Sources/App/Text.swift", line: 8)),
        ])
    }
}
