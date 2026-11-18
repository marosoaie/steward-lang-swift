import SwiftSyntax

/// A type as it's spelled in the source, such as `[String: Int]` or
/// `Result<Data, any Error>`.
///
/// Rules match types by spelling, not by what they resolve to: `Int?` and
/// `Optional<Int>` are different names, and so are `Swift.Int` and `Int`.
/// Two names are equal when they're spelled the same apart from whitespace
/// that doesn't separate two words, so `[String:Int]` in the source equals
/// the literal `"[String: Int]"`, but `any Error` doesn't equal `anyError`;
/// comments inside a type don't count:
///
/// ```swift
/// file.functions.filter { $0.returnType == "LoadResult" }
/// ```
public struct TypeName: Sendable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The spelling, without comments, and with each run of whitespace or
    /// line breaks between two tokens written as one space.
    public var spelling: String

    /// Creates a name with this spelling.
    public init(_ spelling: String) {
        self.spelling = spelling
    }

    /// Creates a name from a string literal, so a rule can compare with one.
    public init(stringLiteral spelling: String) {
        self.init(spelling)
    }

    /// The spelling.
    public var description: String {
        spelling
    }

    /// Whether the two names are spelled the same apart from whitespace
    /// that doesn't separate two words.
    public static func == (lhs: TypeName, rhs: TypeName) -> Bool {
        lhs.comparableSpelling == rhs.comparableSpelling
    }

    /// Hashes the spelling as `==` compares it.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(comparableSpelling)
    }

    /// The spelling with each run of whitespace dropped, unless it
    /// separates two words (`any Error`, `inout Int`), where it's one space.
    private var comparableSpelling: String {
        let scalars = Array(spelling.unicodeScalars)
        let kept = scalars.indices.compactMap { index -> Unicode.Scalar? in
            let scalar = scalars[index]
            guard scalar.properties.isWhitespace else { return scalar }
            // The run's first space stands for the run, between two words;
            // the rest of the run looks no further, so this stays linear.
            guard index > 0, !scalars[index - 1].properties.isWhitespace else { return nil }
            let after = scalars[index...].first { !$0.properties.isWhitespace }
            return scalars[index - 1].isWordScalar && (after?.isWordScalar ?? false) ? " " : nil
        }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: kept)
        return String(result)
    }
}

extension Unicode.Scalar {
    /// Whether the scalar can be part of an identifier or a keyword: every
    /// one beyond ASCII counts, since identifiers can hold emoji and other
    /// symbols.
    fileprivate var isWordScalar: Bool {
        value >= 0x80 || properties.isAlphabetic || properties.numericType != nil || self == "_" || self == "$"
    }
}

extension TypeName {
    /// The spelling of `type` as the source writes it, without trivia.
    init(_ type: some SyntaxProtocol) {
        self.init(type.spelling)
    }
}
