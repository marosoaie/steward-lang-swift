import SwiftSyntax

/// Doc comments, read as the compiler reads them for its symbol graph,
/// which `SymbolGraphOracleTests` holds this reading to.
enum Documentation {
    /// The text of `declaration`'s doc comment, or nil when it has none.
    ///
    /// The doc comment is the last run of `///` and `/** */` comments in
    /// the trivia before the declaration's first token. Comments on
    /// consecutive lines are one run, a plain `//` or `/* */` comment among
    /// them included, and a blank line before a doc comment starts a new
    /// run; nothing after the run detaches it. Each comment loses its
    /// markers, and a block comment that starts with a line break loses
    /// that line, and its ` * ` decoration when the first line has it,
    /// aligned under the `/**`. Each line then loses as much of its leading
    /// whitespace as the run's first non-empty line has, and whitespace-only
    /// lines at the start and the end are dropped, which the compiler keeps.
    /// The markers, the decoration and the whitespace are dropped by Unicode
    /// scalar, as the compiler drops them by byte, so a combining mark after
    /// them stays.
    ///
    /// Where the compiler, as of Swift 6.4, reads otherwise: a block
    /// comment's CRLF line ends read as LF; a decorated block comment's
    /// `**/` loses its star as decoration, which the compiler keeps as a
    /// line of text; and a doc comment that trails code is in that line's
    /// trailing trivia, not here, where the compiler counts it.
    static func text(of declaration: some SyntaxProtocol, lines: SourceLines) -> String? {
        // An imperative loop: the run so far, and the line breaks since the
        // last comment, are the state.
        var run: [Substring] = []
        var isInRun = false
        var breaks = 2
        var offset = declaration.position.utf8Offset
        for piece in declaration.leadingTrivia.pieces {
            defer { offset += piece.sourceLength.utf8Length }
            let comment: [Substring]
            switch piece {
            case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
                breaks += count
                continue
            case .docLineComment(let text):
                comment = [Substring(text.unicodeScalars.dropFirst(3))]
            case .docBlockComment(let text):
                comment = blockLines(text, column: lines.column(atUTF8Offset: offset))
            case .blockComment("/**/"):
                // A plain comment for swift-syntax, but an empty doc comment
                // for the compiler.
                comment = []
            case .lineComment, .blockComment:
                breaks = 0
                continue
            default:
                continue
            }
            // A doc comment after a blank line starts a new run.
            if breaks > 1 { run = [] }
            run += comment
            isInRun = true
            breaks = 0
        }
        guard isInRun else { return nil }
        let indentation = run.first { !$0.isEmpty }.map(\.indentation) ?? 0
        let unindented = run.map { Substring($0.unicodeScalars.dropFirst(Swift.min(indentation, $0.indentation))) }
        let isBlank = { (line: Substring) in line.unicodeScalars.allSatisfy(\.isIndentation) }
        let lastText = unindented.lastIndex { !isBlank($0) } ?? -1
        return unindented.prefix(lastText + 1).drop(while: isBlank).joined(separator: "\n")
    }

    /// The lines of a `/** */` comment that starts at `column`, without its
    /// markers, its first line when that line is empty, and its ` * `
    /// decoration when the first line after that has it. A line break at
    /// the end of the body ends its last line, and starts no other.
    private static func blockLines(_ text: String, column: Int) -> [Substring] {
        var body = Substring(text.unicodeScalars.dropFirst(3))
        if body.unicodeScalars.suffix(2).elementsEqual("*/".unicodeScalars) {
            body = Substring(body.unicodeScalars.dropLast(2))
        }
        var lines = body.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }
        let startsWithBreak = lines.count > 1 && lines[0].isEmpty
        if startsWithBreak {
            lines.removeFirst()
        }
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        // The decoration starts after as many spaces as there are columns
        // before the `/**`.
        let spaces = column - 1
        guard startsWithBreak, let first = lines.first, decoration(of: first, afterSpaces: spaces) > 0 else {
            return lines
        }
        return lines.map { Substring($0.unicodeScalars.dropFirst(decoration(of: $0, afterSpaces: spaces))) }
    }

    /// The length of `line`'s decoration, in scalars: `spaces` spaces, then
    /// ` * ` or a final ` *`, or 0 when it has none. A final ` *` counts on
    /// the body's last line too, where a `**/` closer leaves one, which the
    /// compiler reads as text.
    private static func decoration(of line: Substring, afterSpaces spaces: Int) -> Int {
        let bytes = line.utf8
        guard bytes.count >= spaces + 2, bytes.prefix(spaces).allSatisfy({ $0 == UInt8(ascii: " ") }) else {
            return 0
        }
        let rest = bytes.dropFirst(spaces)
        if rest.starts(with: " * ".utf8) {
            return spaces + 3
        }
        return rest.elementsEqual(" *".utf8) ? spaces + 2 : 0
    }
}

extension Substring {
    /// How many whitespace scalars the line starts with, as the compiler
    /// counts indentation.
    fileprivate var indentation: Int {
        unicodeScalars.prefix(while: \.isIndentation).count
    }
}

extension Unicode.Scalar {
    /// Whether the compiler counts the scalar as indentation: a space, a
    /// tab, a vertical tab or a form feed.
    fileprivate var isIndentation: Bool {
        self == " " || self == "\t" || self == "\u{0B}" || self == "\u{0C}"
    }
}
