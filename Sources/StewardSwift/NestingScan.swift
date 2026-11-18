/// A scan of a source's bytes, before the parser sees them, for the shapes
/// that swift-syntax's parser can't read within bounded stack, memory or
/// time, whatever the stack it runs on (measured with swift-syntax 604):
///
/// - Nested `[` that open array literals or array types take time that
///   doubles with each level, in every build configuration: 26 levels take
///   seconds, 40 would take days. The cost adds up over a file, so it's
///   budgeted per file, at about two to the power of each `[`'s depth.
/// - Generic arguments (`A<A<…`, and comparisons the parser tries as
///   generic arguments), `#if` blocks and string interpolations recurse
///   without the parser's nesting limit: a few thousand levels overflow
///   even a 64 MiB stack, and 100,000 interpolations exhaust memory.
///
/// The scan reads the source twice. The first pass follows comments and
/// string literals, so brackets in them don't count. It isn't a lexer,
/// though, and a regex literal holding a quote can put it out of step
/// with the parser for the rest of a line. So a second pass counts the
/// shapes that crash or exhaust memory (all but `[`) without telling code
/// from literals, interpolations by the parentheses that close them. A
/// shape past its limit in either pass is an excess. Neither pass is a
/// guarantee: `SwiftFile`'s time limit is the backstop for what gets past
/// them.
struct NestingScan {
    /// A shape the scan found nested too deeply, and the line where it
    /// went past its limit (`Shape` says what each one is).
    struct Excess: Sendable, Hashable {
        var shape: Shape
        var line: Int
    }

    typealias Shape = SwiftFile.NestingShape

    /// Each `[` costs two to the power of its depth, so a run of 21 nested
    /// ones uses the budget up: about 0.4 s of parsing in a release build,
    /// and 12 s in a debug one. A 1 MB file of ordinary code costs a few
    /// hundred thousand.
    static let squareBracketBudget = 1 << 22
    /// Far from the depth that overflows the parser's stack (thousands)
    /// and from what real code writes (a few).
    static let angleBracketDepth = 512
    static let conditionalDepth = 512
    static let interpolationDepth = 512

    /// The first shape that goes past its limit in `source`, if one does.
    static func firstExcess(in source: String) -> Excess? {
        let bytes = Array(source.utf8)
        var followingLiterals = Scanner(bytes: bytes, followsLiterals: true)
        var bare = Scanner(bytes: bytes, followsLiterals: false)
        return followingLiterals.run() ?? bare.run()
    }
}

/// The scan's state: where it is, what it's inside, and how deep each
/// counted shape is.
private struct Scanner {
    private enum Context {
        /// Code at the top level, or inside an interpolation, which ends at
        /// the `)` that balances its `\(`.
        case code(openParentheses: Int, isInterpolation: Bool)
        /// A string literal, with the number of `#` around it.
        case string(hashes: Int, isMultiline: Bool)
    }

    private let bytes: [UInt8]
    /// Whether comments and string literals are told from code. When they
    /// aren't, `[` isn't counted: a string such as `"["` would add up.
    private let followsLiterals: Bool
    private var index = 0
    private var line = 1
    /// Whether only spaces and tabs come before the cursor on its line.
    private var isAtStartOfLine = true
    private var contexts: [Context] = [.code(openParentheses: 0, isInterpolation: false)]
    private var interpolations = 0
    private var squareBrackets = 0
    private var squareBracketCost = 0
    private var angleBrackets = 0
    private var conditionals = 0

    init(bytes: [UInt8], followsLiterals: Bool) {
        self.bytes = bytes
        self.followsLiterals = followsLiterals
    }

    // An imperative loop: a cursor over bytes whose next step depends on
    // what it's inside, which combinators would obscure.
    mutating func run() -> NestingScan.Excess? {
        while index < bytes.count {
            let excess: NestingScan.Shape?
            switch contexts.last {
            case .string(let hashes, let isMultiline):
                excess = scanString(hashes: hashes, isMultiline: isMultiline)
            case .code(let openParentheses, let isInterpolation):
                excess = scanCode(openParentheses: openParentheses, isInterpolation: isInterpolation)
            case nil:
                excess = nil
                contexts = [.code(openParentheses: 0, isInterpolation: false)]
            }
            if let excess {
                return NestingScan.Excess(shape: excess, line: line)
            }
        }
        return nil
    }

    private func byte(at offset: Int) -> UInt8? {
        bytes.indices.contains(index + offset) ? bytes[index + offset] : nil
    }

    private mutating func advance(by count: Int = 1) {
        let end = Swift.min(index + count, bytes.count)
        bytes[index..<end].forEach { byte in
            if byte == UInt8(ascii: "\n") {
                line += 1
                isAtStartOfLine = true
            } else if byte != UInt8(ascii: " ") && byte != UInt8(ascii: "\t") {
                isAtStartOfLine = false
            }
        }
        index = end
    }

    // MARK: Code

    private mutating func scanCode(openParentheses: Int, isInterpolation: Bool) -> NestingScan.Shape? {
        guard let current = byte(at: 0) else { return nil }
        switch current {
        case UInt8(ascii: "/") where followsLiterals && byte(at: 1) == UInt8(ascii: "/"):
            skipLineComment()
        case UInt8(ascii: "/") where followsLiterals && byte(at: 1) == UInt8(ascii: "*"):
            skipBlockComment()
        case UInt8(ascii: "\""), UInt8(ascii: "#"):
            return scanStringStartOrDirective()
        case UInt8(ascii: "\\"):
            return scanBackslash()
        case UInt8(ascii: "("), UInt8(ascii: ")"):
            scanParenthesis(openParentheses: openParentheses, isInterpolation: isInterpolation)
        case UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: "<"), UInt8(ascii: ">"):
            return scanBracket(current)
        case UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: ";"):
            // Generic arguments can't hold these, so no `<` before one is
            // still open.
            angleBrackets = 0
            advance()
        case UInt8(ascii: "="):
            scanEquals()
        default:
            advance()
        }
        return nil
    }

    /// A `(` or a `)`, which ends an interpolation when it balances its
    /// `\(`.
    private mutating func scanParenthesis(openParentheses: Int, isInterpolation: Bool) {
        if byte(at: 0) == UInt8(ascii: "(") {
            replaceTop(with: .code(openParentheses: openParentheses + 1, isInterpolation: isInterpolation))
        } else if isInterpolation && openParentheses == 0 {
            contexts.removeLast()
            interpolations -= 1
        } else {
            let open = Swift.max(0, openParentheses - 1)
            replaceTop(with: .code(openParentheses: open, isInterpolation: isInterpolation))
        }
        advance()
    }

    /// A `[`, `]`, `<` or `>`.
    private mutating func scanBracket(_ bracket: UInt8) -> NestingScan.Shape? {
        switch bracket {
        case UInt8(ascii: "["):
            advance()
            return openSquareBracket()
        case UInt8(ascii: "]"):
            squareBrackets = Swift.max(0, squareBrackets - 1)
            advance()
        case UInt8(ascii: "<"):
            return scanLessThan()
        default:
            // `->` and `>=` don't close generic arguments.
            if index == 0 || bytes[index - 1] != UInt8(ascii: "-"), byte(at: 1) != UInt8(ascii: "=") {
                angleBrackets = Swift.max(0, angleBrackets - 1)
            }
            advance()
        }
        return nil
    }

    private mutating func openSquareBracket() -> NestingScan.Shape? {
        guard followsLiterals else { return nil }
        squareBrackets += 1
        // The budget is spent by depth 22, so the shift never overflows.
        squareBracketCost += 1 << Swift.min(squareBrackets, 62)
        return squareBracketCost > NestingScan.squareBracketBudget ? .squareBrackets : nil
    }

    /// A `\` in code: a string's interpolation when the second pass reads
    /// strings as code, and otherwise text the parser rejects.
    private mutating func scanBackslash() -> NestingScan.Shape? {
        let hashes = bytes[(index + 1)...].prefix { $0 == UInt8(ascii: "#") }.count
        guard byte(at: hashes + 1) == UInt8(ascii: "(") else {
            advance()
            return nil
        }
        advance(by: hashes + 2)
        return openInterpolation()
    }

    private mutating func openInterpolation() -> NestingScan.Shape? {
        contexts.append(.code(openParentheses: 0, isInterpolation: true))
        interpolations += 1
        return interpolations > NestingScan.interpolationDepth ? .interpolation : nil
    }

    private mutating func scanLessThan() -> NestingScan.Shape? {
        let isOperator = byte(at: 1) == UInt8(ascii: "<") || byte(at: 1) == UInt8(ascii: "=")
            || (index > 0 && bytes[index - 1] == UInt8(ascii: "."))
        advance(by: isOperator ? 2 : 1)
        guard !isOperator else { return nil }
        angleBrackets += 1
        return angleBrackets > NestingScan.angleBracketDepth ? .angleBrackets : nil
    }

    private mutating func scanEquals() {
        // An assignment ends whatever generic arguments came before it;
        // `==`, `!=`, `<=`, `>=` and the like don't.
        let previous = index > 0 ? bytes[index - 1] : 0
        let isPartOfOperator = byte(at: 1) == UInt8(ascii: "=")
            || [UInt8(ascii: "="), UInt8(ascii: "!"), UInt8(ascii: "<"), UInt8(ascii: ">")].contains(previous)
        if !isPartOfOperator {
            angleBrackets = 0
        }
        advance(by: byte(at: 1) == UInt8(ascii: "=") ? 2 : 1)
    }

    private mutating func skipLineComment() {
        let end = bytes[index...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.count
        advance(by: end - index)
    }

    // An imperative loop: block comments nest, so the end depends on a
    // count kept while scanning.
    private mutating func skipBlockComment() {
        var depth = 0
        repeat {
            if byte(at: 0) == UInt8(ascii: "/") && byte(at: 1) == UInt8(ascii: "*") {
                depth += 1
                advance(by: 2)
            } else if byte(at: 0) == UInt8(ascii: "*") && byte(at: 1) == UInt8(ascii: "/") {
                depth -= 1
                advance(by: 2)
            } else {
                advance()
            }
        } while depth > 0 && index < bytes.count
    }

    /// A string literal's opening quotes, raw or not, or a `#if` or
    /// `#endif` at the start of a line; any other `#` is skipped.
    private mutating func scanStringStartOrDirective() -> NestingScan.Shape? {
        let hashes = bytes[index...].prefix { $0 == UInt8(ascii: "#") }.count
        if followsLiterals, byte(at: hashes) == UInt8(ascii: "\"") {
            let isMultiline = byte(at: hashes + 1) == UInt8(ascii: "\"") && byte(at: hashes + 2) == UInt8(ascii: "\"")
            advance(by: hashes + (isMultiline ? 3 : 1))
            contexts.append(.string(hashes: hashes, isMultiline: isMultiline))
            return nil
        }
        if hashes == 1, isAtStartOfLine {
            if matchesWord("if", at: 1) {
                conditionals += 1
                advance(by: 3)
                return conditionals > NestingScan.conditionalDepth ? .conditionalCompilation : nil
            }
            if matchesWord("endif", at: 1) {
                conditionals = Swift.max(0, conditionals - 1)
                advance(by: 6)
                return nil
            }
        }
        advance(by: Swift.max(1, hashes))
        return nil
    }

    /// Whether `word` is at `offset` from the cursor, followed by something
    /// that can't continue an identifier.
    private func matchesWord(_ word: String, at offset: Int) -> Bool {
        let letters = Array(word.utf8)
        let matches = letters.indices.allSatisfy { byte(at: offset + $0) == letters[$0] }
        guard matches, let next = byte(at: offset + letters.count) else { return matches }
        return !(next.isASCIILetterOrDigit || next == UInt8(ascii: "_"))
    }

    private mutating func replaceTop(with context: Context) {
        contexts[contexts.count - 1] = context
    }

    // MARK: Strings

    private mutating func scanString(hashes: Int, isMultiline: Bool) -> NestingScan.Shape? {
        guard let current = byte(at: 0) else { return nil }
        switch current {
        case UInt8(ascii: "\\") where (0..<hashes).allSatisfy({ byte(at: 1 + $0) == UInt8(ascii: "#") }):
            if byte(at: hashes + 1) == UInt8(ascii: "(") {
                advance(by: hashes + 2)
                return openInterpolation()
            }
            advance(by: hashes + 2)
        case UInt8(ascii: "\"") where closesString(hashes: hashes, isMultiline: isMultiline):
            advance(by: (isMultiline ? 3 : 1) + hashes)
            contexts.removeLast()
        case UInt8(ascii: "\n") where !isMultiline:
            // An unterminated single-line string ends at the line's end, as
            // the parser recovers.
            contexts.removeLast()
        default:
            advance()
        }
        return nil
    }

    private func closesString(hashes: Int, isMultiline: Bool) -> Bool {
        let quotes = isMultiline ? 3 : 1
        return (0..<quotes).allSatisfy { byte(at: $0) == UInt8(ascii: "\"") }
            && (0..<hashes).allSatisfy { byte(at: quotes + $0) == UInt8(ascii: "#") }
    }
}

extension UInt8 {
    fileprivate var isASCIILetterOrDigit: Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(self)
    }
}
