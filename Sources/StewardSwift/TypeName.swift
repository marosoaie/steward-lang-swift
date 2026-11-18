import SwiftSyntax

/// A type as it's spelled in the source, such as `[String: Int]` or
/// `Result<Data, any Error>`.
///
/// Rules match types by spelling, not by what they resolve to: `Int?` and
/// `Optional<Int>` are different names, and so are `Swift.Int` and `Int`.
/// Two names are equal when they're spelled the same apart from whitespace,
/// so `[String:Int]` in the source equals the literal `"[String: Int]"`, and
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

    /// Whether the two names are spelled the same apart from whitespace.
    public static func == (lhs: TypeName, rhs: TypeName) -> Bool {
        lhs.comparableSpelling.elementsEqual(rhs.comparableSpelling)
    }

    /// Hashes the spelling without its whitespace, as `==` compares it.
    public func hash(into hasher: inout Hasher) {
        comparableSpelling.forEach { hasher.combine($0) }
    }

    private var comparableSpelling: some Sequence<Unicode.Scalar> {
        spelling.unicodeScalars.lazy.filter { !$0.properties.isWhitespace }
    }
}

extension TypeName {
    /// The spelling of `type` as the source writes it, without trivia.
    init(_ type: some SyntaxProtocol) {
        self.init(type.spelling)
    }
}
