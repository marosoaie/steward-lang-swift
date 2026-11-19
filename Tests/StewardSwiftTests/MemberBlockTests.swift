import StewardSwift
import StewardTesting
import Testing

@Suite("Member blocks and members")
struct MemberBlockTests {
    @Test("member blocks are every type's and extension's, in source order, with their owners")
    func owners() async throws {
        let blocks = try await Sample.file("""
            struct Loader {
                enum State {}
            }
            extension Loader.State: Equatable {}
            public extension [String: Int] {}
            protocol Fetching {}
            """).memberBlocks
        #expect(blocks.map(\.owner) == [
            .type(.struct, name: "Loader"),
            .type(.enum, name: "State"),
            .extension("Loader.State"),
            .extension("[String: Int]"),
            .type(.protocol, name: "Fetching"),
        ])
        #expect(blocks.map(\.owner.description) == [
            "struct Loader", "enum State", "extension Loader.State", "extension [String: Int]", "protocol Fetching",
        ])
        #expect(blocks.map(\.location.line) == [1, 2, 4, 5, 6])
        #expect(blocks[3].access == AccessLevel(level: .public, isExplicit: true))
    }

    @Test("a block has its owner's inherited types and attributes, an extension's conformances among them")
    func ownersConformances() async throws {
        let blocks = try await Sample.file("""
            @MainActor
            final class Cache: NSObject {}
            @available(macOS 26, *)
            extension Cache: @unchecked Sendable, Identifiable {}
            """).memberBlocks
        #expect(blocks.map(\.inheritedTypes) == [["NSObject"], ["@unchecked Sendable", "Identifiable"]])
        #expect(blocks.map { $0.attributes.map(\.name) } == [["MainActor"], ["available"]])
    }

    @Test("members are listed in source order, one for each name, with their kinds")
    func membersInOrder() async throws {
        let block = try #require(try await Sample.file("""
            struct S {
                typealias ID = String
                static let shared = S()
                var a, b: Int
                let (c, d) = (1, 2)
                init() {}
                func load() {}
                subscript(index: Int) -> Int { index }
                struct Nested {}
                #warning("todo")
                deinit {}
            }
            """).memberBlocks.first)
        let members = block.members.map { "\($0.kind) \($0.name)" }
        #expect(members == [
            "typeAlias ID", "property shared", "property a", "property b", "property c", "property d",
            "initializer init", "function load", "subscript subscript", "type Nested",
            "macroExpansion warning", "deinitializer deinit",
        ])
        #expect(block.members.map(\.isStatic) == [false, true] + Array(repeating: false, count: 10))
    }

    @Test(
        "an enum's cases and a deinit have their type's access level, but at least internal",
        arguments: [
            ("public enum S { case a }", AccessLevel.Level.public),
            ("package enum S { case a }", .package),
            ("enum S { case a }", .internal),
            ("fileprivate enum S { case a }", .internal),
            ("private enum S { case a }", .internal),
            ("open class S { deinit {} }", .open),
            ("public struct S: ~Copyable { deinit {} }", .public),
            ("public actor S { deinit {} }", .public),
            ("fileprivate class S { deinit {} }", .internal),
        ]
    )
    func implicitMemberAccess(source: String, level: AccessLevel.Level) async throws {
        let member = try #require(try await Sample.file(source).memberBlocks.first?.members.first)
        #expect(member.access == AccessLevel(level: level, isExplicit: false))
    }

    @Test("an enum's cases are members, with the enum's access level")
    func enumCases() async throws {
        let block = try #require(try await Sample.file("""
            public enum State {
                case idle, loading
                case done(Int)
                private func helper() {}
            }
            """).memberBlocks.first)
        #expect(block.members.map(\.name) == ["idle", "loading", "done", "helper"])
        #expect(block.members.map(\.access) == [
            AccessLevel(level: .public, isExplicit: false),
            AccessLevel(level: .public, isExplicit: false),
            AccessLevel(level: .public, isExplicit: false),
            AccessLevel(level: .private, isExplicit: true),
        ])
    }

    @Test("a protocol's requirements are members")
    func protocolRequirements() async throws {
        let block = try #require(try await Sample.file("""
            protocol Loader {
                associatedtype Output
                var name: String { get }
                func load() async throws -> Output
                static func make() -> Self
            }
            """).memberBlocks.first)
        #expect(block.members.map(\.kind) == [.associatedType, .property, .function, .function])
        #expect(block.functions.map(\.name) == ["load", "make"])
    }

    @Test("every #if branch's members are read, in source order, and marked as conditional")
    func conditionalMembers() async throws {
        let block = try #require(try await Sample.file("""
            struct S {
                func always() {}
                #if os(macOS)
                func onMacOS() {}
                #elseif os(Linux)
                #if DEBUG
                func onLinuxDebug() {}
                #endif
                #else
                var elsewhere: Int
                #endif
                func after() {}
            }
            """).memberBlocks.first)
        #expect(block.members.map(\.name) == ["always", "onMacOS", "onLinuxDebug", "elsewhere", "after"])
        #expect(block.members.map(\.isConditional) == [false, true, true, true, false])
        #expect(block.functions.map(\.name) == ["always", "onMacOS", "onLinuxDebug", "after"])
    }

    @Test("a block's functions are its own members, not functions in their bodies")
    func ownFunctionsOnly() async throws {
        let block = try #require(try await Sample.file("""
            struct S {
                func outer() {
                    func inner() {}
                }
                var computed: Int {
                    func local() -> Int { 0 }
                    return local()
                }
            }
            """).memberBlocks.first)
        #expect(block.functions.map(\.name) == ["outer"])
    }

    @Test("a member's location is its name's line, and its lines are its declaration's")
    func memberLocations() async throws {
        let block = try #require(try await Sample.file("""
            struct S {
                /// The name.
                @available(*, deprecated)
                public var
                    name: String,
                    other: Int
            }
            """).memberBlocks.first)
        #expect(block.members.map(\.location.line) == [5, 6])
        #expect(block.members.map(\.lines) == [3...6, 3...6])
        #expect(block.lines == 1...7)
    }

    @Test("an ordering rule reads a block's functions in order")
    func orderingRecipe() async throws {
        let blocks = try await Sample.file("""
            struct S {
                func a() {}
                private func b() {}
                func c() {}
            }
            extension S {
                func d() {}
                private func e() {}
            }
            """).memberBlocks
        // Private functions come last in their type or extension.
        let misplaced = blocks.flatMap { block in
            block.functions.drop { $0.access.level != .private }.filter { $0.access.level != .private }
        }
        #expect(misplaced.map(\.name) == ["c"])
    }
}
