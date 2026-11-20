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
            // Precomposed and decomposed, as the compiler tells them apart.
            ("Caf\u{E9}", "Cafe\u{301}"),
        ]
    )
    func spellingNotResolution(lhs: String, rhs: String) {
        #expect(TypeName(lhs) != TypeName(rhs))
    }

    @Test("names compare and hash as their spellings do with whitespace normalized, whatever the whitespace")
    func comparisonMatchesNormalization() {
        // The normalization `==` and `hash(into:)` follow, built in full, as
        // TypeName did before it compared scalar by scalar.
        func normalized(_ spelling: String) -> String {
            let scalars = Array(spelling.unicodeScalars)
            let isWord = { (scalar: Unicode.Scalar) in
                scalar.value >= 0x80 || scalar.properties.isAlphabetic || scalar.properties.numericType != nil
                    || scalar == "_" || scalar == "$"
            }
            let kept = scalars.indices.compactMap { index -> Unicode.Scalar? in
                let scalar = scalars[index]
                guard scalar.properties.isWhitespace else { return scalar }
                guard index > 0, !scalars[index - 1].properties.isWhitespace else { return nil }
                let after = scalars[index...].first { !$0.properties.isWhitespace }
                return isWord(scalars[index - 1]) && (after.map(isWord) ?? false) ? " " : nil
            }
            return String(String.UnicodeScalarView(kept))
        }
        let bases = [
            "[String: Int]", "any Error", "anyError", "inout Int", "Result<Data, any Error>", "some P",
            "(Int) async throws -> Void", "any 😀", "any😀", "Dictionary<String, [Int]>", "@escaping () -> Void",
            "Int?", "$T", "_Foo", "a1 b2", "a1b2", "Combine.Published", "é x", "",
        ]
        let whitespace = [" ", "  ", "\t", "\n", "\r\n", "\u{A0}", "\u{2003}", " \n\t ", "\u{3000}"]
        var generator = SeededGenerator(seed: 16)
        let variants = bases.flatMap { base in
            (0..<12).map { _ in
                var scalars = Array(base.unicodeScalars)
                (0..<Int.random(in: 1...3, using: &generator)).forEach { _ in
                    let at = Int.random(in: 0...scalars.count, using: &generator)
                    scalars.insert(contentsOf: whitespace.randomElement(using: &generator)!.unicodeScalars, at: at)
                }
                return String(String.UnicodeScalarView(scalars))
            }
        }
        let spellings = bases + variants
        let differing = spellings.flatMap { lhs in
            spellings.compactMap { rhs -> String? in
                let (left, right) = (TypeName(lhs), TypeName(rhs))
                let equal = normalized(lhs) == normalized(rhs)
                guard left == right, equal else {
                    return left == right || equal ? "\(lhs.debugDescription) and \(rhs.debugDescription)" : nil
                }
                let names = "\(lhs.debugDescription), \(rhs.debugDescription)"
                return left.hashValue == right.hashValue ? nil : "hashes of \(names)"
            }
        }
        #expect(spellings.count > 200)
        #expect(differing.isEmpty, "\(differing.count): \(differing.prefix(10))")
    }

    @Test("comparing a long name with a short one reads only as far as they differ")
    func comparisonStopsEarly() {
        // `var a0, a1, …: (Int, Int, …)` lends one long type to every name,
        // and a rule compares each with a short one. Built in full, a
        // comparison read all of the long one: 100 here took seconds.
        let long = TypeName("(" + String(repeating: "Int, ", count: 200_000) + "Int)")
        let clock = ContinuousClock()
        var equal = 0
        let elapsed = clock.measure { equal = (0..<100).count { _ in long == "Int" || long == "(Int)" } }
        #expect(equal == 0)
        #expect(elapsed < .seconds(1), "took \(elapsed)")
    }

    @Test("a name compares with a string literal and describes itself by its spelling")
    func literal() {
        let name = TypeName("Result<Data, Error>")
        #expect(name == "Result<Data,Error>")
        #expect(name.description == "Result<Data, Error>")
        #expect("\(name)" == "Result<Data, Error>")
    }
}
