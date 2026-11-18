extension SwiftFile {
    /// A shape whose nesting swift-syntax's parser can't read within
    /// bounded stack, memory or time.
    public enum NestingShape: Sendable, Hashable, CustomStringConvertible {
        /// Nested `[`, which open array literals or types: parse time
        /// doubles with each level.
        case squareBrackets
        /// Unclosed `<`, of generic arguments or comparisons.
        case angleBrackets
        /// `#if` blocks.
        case conditionalCompilation
        /// Interpolations inside string literals.
        case interpolation

        /// The shape, as a finding names it.
        public var description: String {
            switch self {
            case .squareBrackets: "nested `[`"
            case .angleBrackets: "unclosed `<`"
            case .conditionalCompilation: "nested `#if` blocks"
            case .interpolation: "nested string interpolations"
            }
        }

        /// The limit: for `squareBrackets`, a budget each `[` spends
        /// two to the power of its depth from; for the others, a depth.
        public var limit: Int {
            switch self {
            case .squareBrackets: NestingScan.squareBracketBudget
            case .angleBrackets: NestingScan.angleBracketDepth
            case .conditionalCompilation: NestingScan.conditionalDepth
            case .interpolation: NestingScan.interpolationDepth
            }
        }
    }

    /// Why a source wasn't read: what was measured, and the limit it went
    /// past. The description says what to change, for a finding.
    ///
    /// Later releases may add cases, so a `switch` over them needs a
    /// `default`.
    public enum Refusal: Error, Sendable, Equatable, CustomStringConvertible {
        /// `shape` goes past `limit` at `line`, found before parsing.
        case nestingTooDeep(NestingShape, line: Int, limit: Int)
        /// The syntax tree is `depth` levels deep, past `limit`.
        case syntaxTreeTooDeep(depth: Int, limit: Int)
        /// The parse didn't finish within `limit`.
        case timedOut(limit: Duration)
        /// An earlier parse ran out of time and still runs, so no other
        /// starts until it ends.
        case earlierParseStillRunning

        /// What happened, and what an author can change.
        public var description: String {
            switch self {
            case .nestingTooDeep(.squareBrackets, let line, _):
                """
                Line \(line) nests `[` too deeply, or too often, for the Swift parser to read in \
                bounded time. Split the nested arrays into named constants.
                """
            case .nestingTooDeep(let shape, let line, let limit):
                """
                Line \(line) goes past \(limit) \(shape), more than the Swift parser reads safely. \
                Split the construct.
                """
            case .syntaxTreeTooDeep(let depth, let limit):
                """
                The file's syntax tree is \(depth) levels deep, past the \(limit) that rules read \
                safely. Break up its longest expression.
                """
            case .timedOut(let limit):
                """
                The Swift parser didn't finish within \(limit.components.seconds) s, so the file \
                wasn't read.
                """
            case .earlierParseStillRunning:
                """
                An earlier file's parse ran out of time and still runs, so this file wasn't read.
                """
            }
        }
    }
}
