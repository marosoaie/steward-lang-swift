import StewardSwift
import Testing

@Suite("A member's node")
struct MemberSyntaxTests {
    @Test("a member holds its declaration's node, of the kind it declares")
    func declarationNode() throws {
        let file = try Sample.file("""
            struct S {
                typealias ID = String
                var a: Int
                init() {}
                func load() {}
                subscript(index: Int) -> Int { index }
                struct Nested {}
                #warning("todo")
                deinit {}
            }
            enum E { case one }
            protocol P { associatedtype Item }
            """)
        let members = file.memberBlocks.flatMap(\.members)
        #expect(members.map(\.syntax.kind) == [
            .typeAliasDecl, .variableDecl, .initializerDecl, .functionDecl, .subscriptDecl, .structDecl,
            .macroExpansionDecl, .deinitializerDecl, .enumCaseDecl, .associatedTypeDecl,
        ])
        #expect(members.allSatisfy { file.location(of: $0.syntax).line == $0.lineRange.lowerBound })
    }

    @Test("the names one declaration declares share its node, so its id doesn't tell them apart")
    func sharedNode() throws {
        let members = try Sample.file("""
            struct S {
                var a, b: Int
                var c = 0
            }
            enum E {
                case one, two
            }
            """).memberBlocks.flatMap(\.members)
        #expect(members.map(\.name) == ["a", "b", "c", "one", "two"])
        let ids = members.map(\.syntax.id)
        #expect(ids[0] == ids[1] && ids[1] != ids[2] && ids[2] != ids[3])
        #expect(ids[3] == ids[4])
        #expect(members[0].syntax.as(VariableDeclSyntax.self)?.bindings.count == 2)
        #expect(members[3].syntax.as(EnumCaseDeclSyntax.self)?.elements.count == 2)
    }

    @Test("a member's node leads up to the type or extension around it, through an #if")
    func enclosing() throws {
        let file = try Sample.file("""
            struct Loader {
                public var url: URL
                #if DEBUG
                public var a, b: Int
                #endif
            }
            extension Loader {
                public func load() {}
            }
            public protocol Fetching {
                func fetch()
                var limit: Int { get }
            }
            enum State { case idle, done }
            """)
        let found = file.memberBlocks.flatMap { block in
            block.members.map { member in
                let around = sequence(first: Syntax(member.syntax), next: \.parent).dropFirst()
                    .first { $0.isProtocol((any DeclGroupSyntax).self) }
                return (name: member.name, around: around?.kind, isOwner: around?.id == block.syntax.parent?.id)
            }
        }
        #expect(found.map(\.name) == ["url", "a", "b", "load", "fetch", "limit", "idle", "done"])
        #expect(found.map(\.around) == [
            .structDecl, .structDecl, .structDecl, .extensionDecl, .protocolDecl, .protocolDecl, .enumDecl, .enumDecl,
        ])
        #expect(found.allSatisfy { $0.isOwner })
    }

    @Test("a type's members hold the same nodes as its block's")
    func typeAndBlockAgree() throws {
        let file = try Sample.file("""
            public struct Feed {
                var a, b: Int
                func refresh() {}
            }
            """)
        let type = try #require(file.types.first)
        let block = try #require(file.memberBlocks.first)
        #expect(type.members.map(\.syntax.id) == block.members.map(\.syntax.id))
    }
}
