import StewardSwift
import Testing

@Suite("Type names")
struct TypeNameTests {
    @Test(
        "a type's spelling drops comments and writes each gap between tokens as one space",
        arguments: [
            ("[String: Int]", "[String: Int]"),
            ("[String:Int]", "[String:Int]"),
            ("Result<\n    Data, // the payload\n    any Error\n>", "Result< Data, any Error >"),
            ("[ /* counts */ Int]", "[ Int]"),
            ("`Type`", "Type"),
            ("@escaping @Sendable (Int) async throws -> Void", "@escaping @Sendable (Int) async throws -> Void"),
            // A qualified name has nothing around its dots.
            ("Combine .Published", "Combine.Published"),
            ("Combine . Published", "Combine.Published"),
            ("Combine\n    .Published", "Combine.Published"),
            ("[Module /* why */ .Holder]", "[Module.Holder]"),
            ("Result<Module .Value, any Error>", "Result<Module.Value, any Error>"),
            ("Int . Type", "Int.Type"),
        ]
    )
    func spelling(type: String, spelling: String) throws {
        let function = try Sample.function("func f(_ x: \(type)) {}")
        #expect(function.parameters.first?.type.spelling == spelling)
    }

    @Test(
        "two names are equal when they're spelled the same apart from whitespace",
        arguments: [
            ("[String:Int]", "[String: Int]"),
            ("Result<Data,Error>", "Result<Data, Error>"),
            ("( Int )->Void", "(Int) -> Void"),
        ]
    )
    func equalApartFromWhitespace(lhs: String, rhs: String) {
        #expect(TypeName(lhs) == TypeName(rhs))
        #expect(TypeName(lhs).hashValue == TypeName(rhs).hashValue)
        #expect(Set([TypeName(lhs), TypeName(rhs)]).count == 1)
    }

    @Test(
        "names that resolve to the same type but are spelled differently aren't equal",
        arguments: [
            ("Int?", "Optional<Int>"), ("Swift.Int", "Int"), ("[Int]", "Array<Int>"),
            // Whitespace between two words separates them.
            ("any Error", "anyError"), ("some P", "someP"), ("inout Int", "inoutInt"), ("any 😀", "any😀"),
        ]
    )
    func spellingNotResolution(lhs: String, rhs: String) {
        #expect(TypeName(lhs) != TypeName(rhs))
    }

    @Test("a name compares with a string literal and describes itself by its spelling")
    func literal() {
        let name = TypeName("Result<Data, Error>")
        #expect(name == "Result<Data,Error>")
        #expect(name.description == "Result<Data, Error>")
        #expect("\(name)" == "Result<Data, Error>")
    }
}
