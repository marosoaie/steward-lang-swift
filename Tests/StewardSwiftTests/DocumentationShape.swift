import Foundation
import Testing

/// A doc comment before a function, and the text the compiler reads from
/// it: the doc comment's lines in its symbol graph, with whitespace-only
/// lines at the start and the end dropped. `SymbolGraphOracleTests`
/// compiles every shape into one module and holds both the text and the
/// model's reading to the graph; the unit tests hold the model to the text
/// without a compiler.
struct DocumentationShape: Sendable, CustomTestStringConvertible {
    /// The source, with `NAME` for the documented function's name.
    var source: String

    /// The compiler's text, or nil when it reads no doc comment.
    var text: String?

    var testDescription: String {
        source
    }

    /// The source, with its function named `name`.
    func source(naming name: String) -> String {
        source.replacingOccurrences(of: "NAME", with: name)
    }

    static let all: [Self] = [
        // Which comments are the doc comment.
        Self(source: "/// A\npublic func NAME() {}", text: "A"),
        Self(source: "public func NAME() {}", text: nil),
        Self(source: "// A plain comment.\npublic func NAME() {}", text: nil),
        Self(source: "/// A\n\npublic func NAME() {}", text: "A"),
        Self(source: "/// A\n// plain\npublic func NAME() {}", text: "A"),
        Self(source: "/// A\n\n\n// plain\n\npublic func NAME() {}", text: "A"),
        Self(source: "/// A\n/* plain */\npublic func NAME() {}", text: "A"),
        Self(source: "/// A\n\n/// B\npublic func NAME() {}", text: "B"),
        Self(source: "/// A\n// plain\n/// B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/// A\n\n// plain\n/// B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/// A\n// plain\n\n/// B\npublic func NAME() {}", text: "B"),
        Self(source: "/// A\n/*\n plain\n */\n/// B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/// A\n/** B */\npublic func NAME() {}", text: "A\nB "),
        Self(source: "/** A *//** B */\npublic func NAME() {}", text: "A \nB "),
        Self(source: "/// above the if\n#if true\npublic func NAME() {}\n#endif", text: nil),
        Self(source: "#if true\n/// inside the if\npublic func NAME() {}\n#endif", text: "inside the if"),
        Self(source: "/// A\n@available(\n    *, deprecated,\n    message: \"m\"\n)\npublic func NAME() {}", text: "A"),
        Self(source: "/// A\n@available(*, deprecated)\n/// B\npublic func NAME() {}", text: "A"),
        // Line comments: each line loses the first non-empty line's
        // indentation, as far as it has it.
        Self(source: "///no space\n/// one space\npublic func NAME() {}", text: "no space\n one space"),
        Self(source: "///   A\n///  B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/// A\n///\tB\npublic func NAME() {}", text: "A\nB"),
        Self(source: "///\n/// A\n///   B\npublic func NAME() {}", text: "A\n  B"),
        Self(
            source: "/// first\n///\n/// after a blank line\npublic func NAME() {}",
            text: "first\n\nafter a blank line"
        ),
        Self(source: "/// A\n/// \npublic func NAME() {}", text: "A"),
        Self(source: "/// A   \npublic func NAME() {}", text: "A   "),
        Self(source: "//// four\npublic func NAME() {}", text: "/ four"),
        // Markers and whitespace go by scalar: a combining mark after them
        // stays. A vertical tab or a form feed is whitespace too.
        Self(source: "///\u{301}A\npublic func NAME() {}", text: "\u{301}A"),
        Self(source: "/// \u{301}A\n///  B\npublic func NAME() {}", text: "\u{301}A\n B"),
        Self(source: "/**\n * \u{301}A\n */\npublic func NAME() {}", text: "\u{301}A"),
        Self(source: "///\u{0B}A\n///  B\npublic func NAME() {}", text: "A\n B"),
        Self(source: "///\u{0C}A\n///  B\npublic func NAME() {}", text: "A\n B"),
        Self(source: "/// crlf A\r\n/// crlf B\r\npublic func NAME() {}", text: "crlf A\ncrlf B"),
        // Block comments: the decoration goes only when `/**` ends its line
        // and the stars line up under it.
        Self(source: "/** A */\npublic func NAME() {}", text: "A "),
        Self(source: "/***/\npublic func NAME() {}", text: ""),
        Self(source: "/**/\npublic func NAME() {}", text: ""),
        Self(source: "/// A\n/**/\n/// B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/**\n*/\npublic func NAME() {}", text: ""),
        Self(source: "/**\n * A\n *\n*/\npublic func NAME() {}", text: "A"),
        // A line break at the end of a block's body starts no line.
        Self(source: "/**\nText\n*/\n/// More\npublic func NAME() {}", text: "Text\n More"),
        Self(source: "/** A\nB\n*/\n/// C\npublic func NAME() {}", text: "A\nB\nC"),
        Self(source: "/**\nA\n*/\n/**\nB\n*/\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/// A\n/***/\n/// B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/// A\n/**\n*/\n/// B\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/** */\npublic func NAME() {}", text: ""),
        Self(source: "/** A\n * B\n */\npublic func NAME() {}", text: "A\n* B"),
        Self(source: "/**\n A\n */\npublic func NAME() {}", text: "A"),
        Self(source: "/**\n\n   A\n */\npublic func NAME() {}", text: "A"),
        Self(source: "/**\n    A\n  */\npublic func NAME() {}", text: "A"),
        Self(source: "/**\n   A\n     more\n   B\n */\npublic func NAME() {}", text: "A\n  more\nB"),
        Self(source: "/**\n * A\n * B\n */\npublic func NAME() {}", text: "A\nB"),
        Self(source: "/**\n * A\n *\n *   B\n */\npublic func NAME() {}", text: "A\n\n  B"),
        Self(source: "/**\n   * A\n   * B\n   */\npublic func NAME() {}", text: "* A\n* B"),
        Self(
            source: """
                public struct NAMEType {
                    /**
                     * A
                     *
                     * B
                     */
                    public func NAME() {}
                }
                """,
            text: "A\n\nB"
        ),
    ]
}
