import StewardSwift
import Testing

@Suite("Member attributes")
struct MemberAttributeTests {
    @Test("a member's attributes keep their arguments and spelling, and those in every branch of an #if count")
    func memberAttributes() throws {
        let members = try #require(try Sample.file("""
            final class Feed: ObservableObject {
                @Published var items: [Item] = []
                @Combine.Published private(set) var isLoading = false
                @available(*, deprecated, message: "Use items")
                #if DEBUG
                @MainActor
                #else
                @inlinable
                #endif
                var all: [Item] { items }
                var count = 0
            }
            """).memberBlocks.first).members
        let location = { Location(path: Sample.path, line: $0) }
        #expect(members.map(\.name) == ["items", "isLoading", "all", "count"])
        #expect(members.map(\.attributes) == [
            [Attribute(name: "Published", arguments: nil, location: location(2))],
            [Attribute(name: "Combine.Published", arguments: nil, location: location(3))],
            [
                Attribute(name: "available", arguments: #"*, deprecated, message: "Use items""#, location: location(4)),
                Attribute(name: "MainActor", arguments: nil, location: location(6)),
                Attribute(name: "inlinable", arguments: nil, location: location(8)),
            ],
            [],
        ])
    }

    @Test("the names a declaration declares share its attributes, in a type or an extension")
    func sharedAttributes() throws {
        let blocks = try Sample.file("""
            final class Feed {
                @MainActor var a, b: Int
                @MainActor var (c, d) = (1, 2)
                var e = 0
            }
            enum State {
                @available(*, deprecated) case idle, loading
            }
            extension Feed {
                @MainActor static let shared = Feed(), empty = Feed()
            }
            """).memberBlocks
        let attributes = blocks.map { block in block.members.map { "\($0.name) \($0.attributes.map(\.name))" } }
        #expect(attributes == [
            [#"a ["MainActor"]"#, #"b ["MainActor"]"#, #"c ["MainActor"]"#, #"d ["MainActor"]"#, "e []"],
            [#"idle ["available"]"#, #"loading ["available"]"#],
            [#"shared ["MainActor"]"#, #"empty ["MainActor"]"#],
        ])
    }

    @Test("every kind of member carries its attributes")
    func everyKindsAttributes() throws {
        let members = try Sample.file("""
            class C {
                @Marked func function() {}
                @Marked init() {}
                @Marked deinit {}
                @Marked subscript(index: Int) -> Int { index }
                @Marked var property = 0
                @Marked struct Nested {}
                @Marked typealias Alias = Int
                @Marked #warning("macro")
            }
            enum E {
                @Marked case value
            }
            protocol P {
                @Marked associatedtype Associated
            }
            """).memberBlocks.flatMap(\.members)
        #expect(members.count == Member.Kind.allCases.count)
        #expect(Set(members.map(\.kind)) == Set(Member.Kind.allCases))
        #expect(members.allSatisfy { $0.attributes.map(\.name) == ["Marked"] })
    }

    @Test("a rule finds the types with a published property, as issue #11 shows it")
    func publishedRecipe() throws {
        let types = try Sample.file("""
            final class Feed: ObservableObject {
                @Published var items: [Item] = []
            }
            final class Settings: ObservableObject {
                @Combine.Published var theme = Theme.system
            }
            final class Cache {
                @MainActor var items: [Item] = []
            }
            """).types
        let published = types.filter { declaration in
            declaration.members.contains { member in
                member.kind == .property && member.attributes.contains { attribute in
                    attribute.name == "Published" || attribute.name == "Combine.Published"
                }
            }
        }
        #expect(published.map(\.name) == ["Feed", "Settings"])
    }
}
