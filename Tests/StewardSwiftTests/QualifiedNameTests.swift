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

    @Test("a dot in an expression keeps the space before it, as in an attribute's arguments")
    func expressionsKeepTheirSpaces() throws {
        let function = try Sample.function("""
            @Option(name: .long, help: Help . text)
            func load() {}
            """)
        #expect(function.attributes.map(\.arguments) == ["name: .long, help: Help . text"])
    }
}
