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
    /// line breaks between two tokens written as one space, but none around
    /// a qualified name's `.` or `::`: `Combine .Published` is
    /// `Combine.Published`.
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
    /// that doesn't separate two words. It reads the spellings only as far
    /// as their first difference, so comparing a long name with a short one
    /// costs the short one's length.
    public static func == (lhs: TypeName, rhs: TypeName) -> Bool {
        lhs.comparableScalars.elementsEqual(rhs.comparableScalars)
    }

    /// Hashes the spelling as `==` compares it.
    public func hash(into hasher: inout Hasher) {
        comparableScalars.forEach { hasher.combine($0.value) }
        // No scalar has this value, so a name's part of a hash ends here.
        hasher.combine(UInt32.max)
    }

    /// The spelling's scalars with each run of whitespace dropped, unless it
    /// separates two words (`any Error`, `inout Int`), where it's one space;
    /// read as they're asked for, with nothing built.
    private var comparableScalars: ComparableScalars {
        ComparableScalars(scalars: spelling.unicodeScalars.makeIterator())
    }
}

/// A spelling's scalars as `TypeName` compares them: each run of whitespace
/// dropped, unless it separates two words, where it's one space.
private struct ComparableScalars: Sequence, IteratorProtocol {
    var scalars: String.UnicodeScalarView.Iterator
    /// The last scalar given, to tell whether a run of whitespace follows a
    /// word.
    var previous: Unicode.Scalar?
    /// The scalar after a run of whitespace, read to see whether the run
    /// separates two words, and given after the space that stands for it.
    var pending: Unicode.Scalar?

    mutating func next() -> Unicode.Scalar? {
        if let scalar = pending {
            pending = nil
            previous = scalar
            return scalar
        }
        guard let scalar = scalars.next() else { return nil }
        guard scalar.isTypeNameWhitespace else {
            previous = scalar
            return scalar
        }
        // An imperative loop: the rest of the run is skipped, and the
        // scalar after it decides whether the run was between two words.
        var after = scalars.next()
        while let next = after, next.isTypeNameWhitespace {
            after = scalars.next()
        }
        guard let next = after else { return nil }
        guard previous?.isWordScalar == true, next.isWordScalar else {
            previous = next
            return next
        }
        pending = next
        previous = " "
        return " "
    }
}

extension Unicode.Scalar {
    /// Whether the scalar is whitespace, as Unicode defines it, without a
    /// look at its properties for ASCII.
    fileprivate var isTypeNameWhitespace: Bool {
        value < 0x80 ? value == 0x20 || (0x09...0x0D).contains(value) : properties.isWhitespace
    }

    /// Whether the scalar can be part of an identifier or a keyword: every
    /// one beyond ASCII counts, since identifiers can hold emoji and other
    /// symbols, and in ASCII, letters, digits, `_` and `$`.
    fileprivate var isWordScalar: Bool {
        value >= 0x80 || ("a"..."z").contains(self) || ("A"..."Z").contains(self) || ("0"..."9").contains(self)
            || self == "_" || self == "$"
    }
}

extension TypeName {
    /// The spelling of `type` as the source writes it, without trivia.
    init(_ type: some SyntaxProtocol) {
        self.init(type.spelling)
    }
}
