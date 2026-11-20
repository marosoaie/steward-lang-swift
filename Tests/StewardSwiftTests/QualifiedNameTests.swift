import StewardSwift
import Testing

@Suite("Qualified names")
struct QualifiedNameTests {
    @Test(
        "a qualified attribute name has nothing around its dots, on every kind of declaration",
        arguments: [
            "Module.Marked", "Module .Marked", "Module . Marked", "Module\n    .Marked",
            "Module /* why */ .Marked", "Module // why\n    .Marked",
        ]
    )
    func attributeNames(spelled: String) throws {
        let file = try Sample.file("""
            @\(spelled) import Foundation
            @\(spelled)
            struct S {
                @\(spelled) var property = 0
                @\(spelled) func method() {}
            }
            @\(spelled)
            extension S {}
            @\(spelled)
            func function() {}
            """)
        #expect(!file.syntax.hasError)
        let one = ["Module.Marked"]
        #expect(file.imports.map { $0.attributes.map(\.name) } == [one])
        #expect(file.types.map { $0.attributes.map(\.name) } == [one])
        #expect(file.memberBlocks.map { $0.attributes.map(\.name) } == [one, one])
        #expect(file.memberBlocks[0].members.map { $0.attributes.map(\.name) } == [one, one])
        #expect(file.functions.map { $0.attributes.map(\.name) } == [one, one])
    }

    @Test("an import's path and an extended type have nothing around their dots")
    func importsAndExtensions() throws {
        let file = try Sample.file("""
            import struct Foundation . Data
            extension Module
                .Holder: Module . Loading {}
            """)
        #expect(!file.syntax.hasError)
        #expect(file.imports.map(\.path) == ["Foundation.Data"])
        #expect(file.imports.map(\.module) == ["Foundation"])
        #expect(file.memberBlocks.map(\.owner) == [.extension("Module.Holder")])
        #expect(file.memberBlocks.map(\.owner.description) == ["extension Module.Holder"])
        #expect(file.memberBlocks.map(\.inheritedTypes.first?.spelling) == ["Module.Loading"])
    }

    @Test("a member access in an expression keeps its spaces, but a type in one doesn't")
    func expressions() throws {
        let function = try Sample.function("""
            @Option(name: .long, help: Help . text)
            func load(retries: Int = 3 as Swift . Int) {}
            """)
        #expect(function.attributes.map(\.arguments) == ["name: .long, help: Help . text"])
        #expect(function.parameters.map(\.defaultValue) == ["3 as Swift.Int"])
    }

    @Test("a generic clause's qualified names have nothing around their dots")
    func genericClauses() throws {
        let function = try Sample.function("""
            func load<T: Module . Loading>(_ item: T) where T . Element == Module
                .Item {}
            """)
        #expect(function.signature.genericParameters == "<T: Module.Loading>")
        #expect(function.signature.genericRequirements == "where T.Element == Module.Item")
    }

    #if canImport(SwiftSyntax603)
    // swift-syntax 603 reads module selectors; 602 has no `::`.
    @Test("a module selector has nothing around its ::, in a type, an attribute or an expression")
    func moduleSelectors() throws {
        let file = try Sample.file("""
            struct S {
                @Module::Marked var a = 0
                @Module :: Marked var b = 0
                @Module :: Inner . Wrap var c = 0
                @Option(help: Module :: text) var d = 0
                func load(_ item: Module :: Item) {}
            }
            """)
        #expect(!file.syntax.hasError)
        let members = try #require(file.memberBlocks.first).members
        #expect(members.prefix(3).map { $0.attributes.map(\.name) } == [
            ["Module::Marked"], ["Module::Marked"], ["Module::Inner.Wrap"],
        ])
        #expect(members[3].attributes.map(\.arguments) == ["help: Module::text"])
        #expect(file.functions.map { $0.parameters.map(\.type) } == [["Module::Item"]])
        #expect(file.functions.first?.parameters.first?.type.spelling == "Module::Item")
    }
    #endif
}
