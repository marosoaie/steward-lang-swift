import StewardSwift
import Testing

/// The README's "What a rule can read": each test's body between its
/// markers is the README's block, word for word.
@Suite("The README: what a rule can read")
struct ReadingExamples {
    @Test("functions")
    func functions() throws {
        // README: read-functions
        let file = try SwiftFile(source: """
            public struct FeedLoader {
                /// Loads the feed at `url`.
                @discardableResult
                public static func load(from url: URL, retries: Int = 3) async throws(LoadError) -> LoadResult {
                    try await fetch(url, retries: retries)
                }
            }
            """, path: "Sources/Feed/FeedLoader.swift")
        let load = file.functions[0]
        #expect(load.name == "load")
        #expect(load.access.level == .public && load.access.isExplicit)
        #expect(load.isStatic && load.isAsync && load.isThrowing)
        #expect(load.signature.thrownType == "LoadError")
        #expect(load.returnType == "LoadResult")
        #expect(load.parameters.map(\.label) == ["from", "retries"])
        #expect(load.parameters.map(\.type) == ["URL", "Int"])
        #expect(load.parameters[1].defaultValue == "3")
        #expect(load.attributes.map(\.name) == ["discardableResult"])
        #expect(load.location == Location(path: "Sources/Feed/FeedLoader.swift", line: 4))
        #expect(load.lines == 3...6)
        // README: end
    }

    @Test("types")
    func types() throws {
        // README: read-types
        let file = try SwiftFile(source: """
            @MainActor
            public final class FeedModel: ObservableObject, Sendable {
                enum State { case idle, loading }
            }
            """, path: "Sources/Feed/FeedModel.swift")
        let model = file.types[0]
        #expect(model.kind == .class && model.isFinal)
        #expect(model.inheritedTypes == ["ObservableObject", "Sendable"])
        #expect(model.attributes.map(\.name) == ["MainActor"])
        #expect(file.types.map(\.name) == ["FeedModel", "State"])
        #expect(file.types[1].access.description == "internal (implicit)")
        // README: end
    }

    @Test("member blocks and members")
    func members() throws {
        // README: read-members
        let file = try SwiftFile(source: """
            struct Feed {
                static let shared = Feed()
                var items: [Item] = []
                init() {}
                func refresh() {}
            }

            extension Feed: Equatable {
                private func merge(_ other: Feed) {}
            }
            """, path: "Sources/Feed/Feed.swift")
        let (feed, extended) = (file.memberBlocks[0], file.memberBlocks[1])
        #expect(feed.members.map(\.kind) == [.property, .property, .initializer, .function])
        #expect(feed.members.map(\.name) == ["shared", "items", "init", "refresh"])
        #expect(feed.members.map(\.isStatic) == [true, false, false, false])
        #expect(extended.owner == .extension("Feed"))
        #expect(extended.inheritedTypes == ["Equatable"])
        #expect(extended.members.map(\.access.level) == [.private])
        // README: end
    }

    @Test("members under #if")
    func conditionalMembers() throws {
        // README: read-conditional-members
        let file = try SwiftFile(source: """
            struct Feed {
                #if DEBUG
                func dump() {}
                #else
                func log() {}
                #endif
                func refresh() {}
            }
            """, path: "Sources/Feed/Feed.swift")
        let members = file.memberBlocks[0].members
        #expect(members.map(\.name) == ["dump", "log", "refresh"])
        #expect(members.map(\.isConditional) == [true, true, false])
        // README: end
    }

    @Test("imports")
    func imports() throws {
        // README: read-imports
        let file = try SwiftFile(source: """
            import Foundation
            @testable import FeedKit
            public import struct Models.Item
            #if canImport(UIKit)
            import UIKit
            #endif
            """, path: "Tests/FeedTests/FeedTests.swift")
        #expect(file.imports.map(\.module) == ["Foundation", "FeedKit", "Models", "UIKit"])
        #expect(file.imports[1].attributes.map(\.name) == ["testable"])
        #expect(file.imports[2].access == .public)
        #expect(file.imports[2].kind == "struct" && file.imports[2].path == "Models.Item")
        #expect(file.imports.map(\.isConditional) == [false, false, false, true])
        // README: end
    }
}
