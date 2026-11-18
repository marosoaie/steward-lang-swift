import SwiftParser
import SwiftSyntax

/// A Swift source file's declarations, read from its syntax.
///
/// ```swift
/// let file = try SwiftFile(source: source, path: "Sources/App/Loader.swift")
/// let findings = file.functions
///     .filter { $0.returnType == "LoadResult" && !$0.isAsync }
///     .map { Finding.failure("\(Markdown.codeSpan($0.name)) should be `async`.", at: $0.location) }
/// ```
///
/// A pull request controls the source, and swift-syntax's parser can't
/// read every source within bounded stack, memory and time, so a source
/// that might not be read safely is refused with a `Refusal` rather than
/// parsed. Let the error fail the rule, as a rule that throws does: a
/// refused file that was skipped instead would let a pull request hide
/// from every rule with one construct.
///
/// The value isn't `Equatable`, and has no memberwise initializer: its
/// declarations come from its tree, and would disagree with it if they
/// were set by hand. It keeps the whole tree alive.
public struct SwiftFile: Sendable {
    /// The path the file has in the repository, which every `location`
    /// names.
    public var path: String

    /// Every `func` declaration, in source order, at any depth: in types,
    /// extensions and protocols, inside other functions and closures, and
    /// in each branch of an `#if`.
    public var functions: [FunctionDeclaration]

    /// The file's syntax tree. It follows swift-syntax's version, not this
    /// package's.
    public var syntax: SourceFileSyntax

    /// Parses `source`, the contents of the file at `path`, and reads its
    /// declarations.
    ///
    /// Source that isn't valid Swift is still read: the parser recovers,
    /// the declarations it can make out are read, and `syntax.hasError`
    /// says whether it had to repair anything. That isn't a refusal.
    ///
    /// The parse runs on a thread of its own, with a 64 MiB stack, and the
    /// calling thread waits for it.
    ///
    /// - Throws: `Refusal` when the source nests a shape too deeply for
    ///   the parser, nests past the parser's limit of 256, its tree is
    ///   too deep for a recursive walk, the parse
    ///   runs out of time (two seconds, and 50 µs a byte), or an earlier
    ///   parse ran out of time and still runs.
    public init(source: String, path: String) throws(Refusal) {
        self = try Self.read(
            source: source,
            path: path,
            timeLimit: Self.timeLimit(forUTF8Count: source.utf8.count),
            gate: .shared
        )
    }

    /// Reads `source` within `timeLimit`, unless `gate` says an earlier
    /// parse still runs.
    static func read(source: String, path: String, timeLimit: Duration, gate: ParseGate) throws(Refusal) -> SwiftFile {
        if let excess = NestingScan.firstExcess(in: source) {
            throw .nestingTooDeep(excess.shape, line: excess.line, limit: excess.shape.limit)
        }
        guard gate.isOpen else { throw .earlierParseStillRunning }
        let outcome = LargeStack.run(timeLimit: timeLimit, gate: gate) { () -> Result<SwiftFile, Refusal> in
            var parser = Parser(source, maximumNestingLevel: Self.maximumNestingLevel)
            let tree = SourceFileSyntax.parse(from: &parser)
            // Past its nesting limit, the parser leaves the rest of the file
            // as unexpected text, so declarations there would be lost.
            guard !tree.hasMaximumNestingLevelOverflow else {
                return .failure(.nestedPastParserLimit(limit: Self.maximumNestingLevel))
            }
            let depth = tree.depth(cappedAt: Self.maximumTreeDepth + 1)
            guard depth <= Self.maximumTreeDepth else {
                return .failure(.syntaxTreeTooDeep(depth: depth, limit: Self.maximumTreeDepth))
            }
            return .success(SwiftFile(tree: tree, source: source, path: path))
        }
        guard let outcome else { throw .timedOut(limit: timeLimit) }
        return try outcome.get()
    }

    private init(tree: SourceFileSyntax, source: String, path: String) {
        let lines = SourceLines(source: source)
        self.path = path
        functions = tree.preorder()
            .compactMap { $0.as(FunctionDeclSyntax.self) }
            .map { FunctionDeclaration($0, path: path, lines: lines) }
        syntax = tree
    }

    /// How deeply the parser follows nested brackets, braces and the like,
    /// in every build configuration: swift-syntax's own default is 256 in
    /// a release build but 20 in a debug build, where a Dangerfile usually
    /// runs, and real code nests deeper than 20.
    static let maximumNestingLevel = 256

    /// The deepest tree read: about half the depth a `SyntaxVisitor` walks
    /// on a 512 KiB stack in a debug build (it dies past about 1,000), so
    /// a rule's own recursive walk has the stack for it on any thread.
    /// Real code's trees are a few dozen levels deep: 93 at most in the
    /// 2,217 files of this package's dependencies.
    static let maximumTreeDepth = 512

    /// Two seconds, and 50 µs for each byte: about twenty times what a
    /// debug build takes for real code (1.1 MB in 2.6 s on an M4), so
    /// only source that parses in more than linear time runs out.
    static func timeLimit(forUTF8Count count: Int) -> Duration {
        .seconds(2) + .microseconds(50) * Swift.min(count, 1 << 40)
    }
}
