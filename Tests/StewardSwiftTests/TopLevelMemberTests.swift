@testable import StewardSwift
import Testing

@Suite("Top-level members")
struct TopLevelMemberTests {
    @Test("the declarations at the top of a file are members, one for each name, in source order")
    func inOrder() throws {
        let file = try Sample.file("""
            import Foundation
            public let version = "1.0"
            var a, b: Int
            typealias ID = String
            func load() {}
            struct Feed {
                var items: [Int] = []
            }
            extension Feed {}
            #warning("todo")
            public macro stringify<T>(_ value: T) -> (T, String) = #externalMacro(module: "M", type: "S")
            infix operator <=>
            print(a)
            """)
        let members = file.topLevelMembers
        // `#warning("todo")`, with no attribute, is an expression here.
        #expect(members.map { "\($0.kind) \($0.name)" } == [
            "property version", "property a", "property b", "typeAlias ID", "function load", "type Feed",
            "macro stringify",
        ])
        #expect(members.map(\.access.description) == [
            "public", "internal (implicit)", "internal (implicit)", "internal (implicit)", "internal (implicit)",
            "internal (implicit)", "public",
        ])
        #expect(members.allSatisfy { !$0.isStatic && !$0.isConditional })
        #expect(members[1].property?.type == "Int" && members[2].property?.type == "Int")
        #expect(members.map(\.location.line) == [2, 3, 3, 4, 5, 6, 11])
    }

    @Test("a rule finds a public global with no doc comment, which no other list holds")
    func undocumentedGlobal() throws {
        let file = try Sample.file("""
            /// The version.
            public let version = "1.0"
            public var verbose = false
            public typealias Handler = () -> Void
            let hidden = 0
            """)
        let undocumented = file.topLevelMembers.filter { $0.access.level >= .public && $0.documentation == nil }
        #expect(undocumented.map(\.name) == ["verbose", "Handler"])
        #expect(file.types.isEmpty && file.functions.isEmpty && file.memberBlocks.isEmpty)
    }

    @Test("every #if branch's top-level members are read, in source order, and marked as conditional")
    func conditional() throws {
        let members = try Sample.file("""
            #if DEBUG
            let level = 2
            #if os(macOS)
            let platform = "macOS"
            #endif
            #else
            let level = 1
            #endif
            let name = ""
            """).topLevelMembers
        #expect(members.map(\.name) == ["level", "platform", "level", "name"])
        #expect(members.map(\.isConditional) == [true, true, true, false])
    }

    @Test("a top-level member holds its declaration's node, shared by the names it declares")
    func node() throws {
        let file = try Sample.file("""
            var a, b: Int

            /// Loads.
            func load() {}
            """)
        let members = file.topLevelMembers
        #expect(members.map(\.syntax.kind) == [.variableDecl, .variableDecl, .functionDecl])
        #expect(members[0].syntax.id == members[1].syntax.id)
        #expect(members.map(\.lineRange) == [1...1, 1...1, 4...4])
        #expect(members[2].documentation == "Loads.")
        #expect(members.allSatisfy { $0.syntax.parent?.parent?.parent?.is(SourceFileSyntax.self) == true })
    }

    @Test("what only a type may declare is read at the top of a file as the source declares it")
    func strayMembers() throws {
        let file = try Sample.file("""
            deinit {}
            init() {}
            subscript(index: Int) -> Int { index }
            associatedtype Item
            @available(*, deprecated) #warning("todo")
            """)
        let members = file.topLevelMembers
        #expect(members.map { "\($0.kind) \($0.name)" } == [
            "deinitializer deinit", "initializer init", "subscript subscript", "associatedType Item",
            "macroExpansion warning",
        ])
        #expect(members.allSatisfy { $0.access == AccessLevel(level: .internal, isExplicit: false) })
        // A stray `case` is a broken `switch` case, which takes in what follows.
        let broken = try Sample.file("case stray\nlet after = 0\n")
        #expect(broken.syntax.hasError && broken.topLevelMembers.isEmpty)
    }

    @Test("a member block's members aren't top-level members, nor are local declarations")
    func onlyTheTop() throws {
        let members = try Sample.file("""
            struct S {
                var a = 0
            }
            func f() {
                let local = 1
                func nested() {}
            }
            let closure = { let inside = 2 }
            """).topLevelMembers
        #expect(members.map(\.name) == ["S", "f", "closure"])
    }

    @Test("a freestanding macro at the top of a file is a member only with an attribute or a modifier")
    func freestandingMacros() throws {
        let members = try Sample.file("""
            #Preview { 1 }
            @available(*, deprecated) #warning("a")
            public #Preview { 2 }
            """).topLevelMembers
        #expect(members.map { "\($0.kind) \($0.name) \($0.access.level)" } == [
            "macroExpansion warning internal", "macroExpansion Preview public",
        ])
    }

    @Test("declarations under ninety-five nested #if blocks at the top are read about as fast as under none")
    func deepConditionalCompilation() throws {
        // A gate and a limit of the test's own, as the index's tests have.
        let read = { (depth: Int) throws -> SwiftFile in
            let declarations = String(repeating: "var a = 0\n", count: 10_000)
            let source = String(repeating: "#if A\n", count: depth) + declarations
                + String(repeating: "#endif\n", count: depth)
            return try SwiftFile.read(source: source, path: Sample.path, timeLimit: .seconds(300), gate: ParseGate())
        }
        let (flat, deep) = (try read(0), try read(95))
        #expect(deep.topLevelMembers.count == 10_000 && deep.topLevelMembers.allSatisfy { $0.isConditional })
        // The faster of five, each way, taken in turns. A walk up to the
        // root for each declaration's default level would take 95 `#if`s'
        // steps for each.
        let members = { (file: SwiftFile, declarations: [DeclSyntax]) in
            declarations.flatMap { declaration in
                Member.all(in: declaration, isConditional: true, owner: nil, path: file.path, lines: file.sourceLines)
            }
        }
        let declarations = { (file: SwiftFile) in
            file.syntax.topLevel.compactMap { $0.as(CodeBlockItemSyntax.self)?.item.as(DeclSyntax.self) }
        }
        let (flatDeclarations, deepDeclarations) = (declarations(flat), declarations(deep))
        let clock = ContinuousClock()
        let rounds = (0..<5).map { _ in
            (
                clock.measure { _ = members(flat, flatDeclarations) },
                clock.measure { _ = members(deep, deepDeclarations) }
            )
        }
        let (flatTime, deepTime) = (rounds.map(\.0).min() ?? .zero, rounds.map(\.1).min() ?? .zero)
        #expect(deepTime < flatTime * 2 + .milliseconds(100), "\(deepTime) under 95 #if, \(flatTime) under none")
    }
}
