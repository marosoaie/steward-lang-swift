import SwiftParser
import SwiftSyntax

/// A Swift source file's declarations, read from its syntax.
///
/// ```swift
/// let file = SwiftFile(source: source, path: "Sources/App/Loader.swift")
/// let findings = file.functions
///     .filter { $0.returnType == "LoadResult" && !$0.isAsync }
///     .map { Finding.failure("\(Markdown.codeSpan($0.name)) should be `async`.", at: $0.location) }
/// ```
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

    /// Parses `source`, the contents of the file at `path`.
    ///
    /// The parse never traps, and recovers from source that isn't valid
    /// Swift: the declarations it can make out are read, and
    /// `syntax.hasError` says whether it had to repair anything.
    public init(source: String, path: String) {
        self = LargeStack.run { SwiftFile(parsing: source, path: path) }
    }

    private init(parsing source: String, path: String) {
        var parser = Parser(source, maximumNestingLevel: Self.maximumNestingLevel)
        let tree = SourceFileSyntax.parse(from: &parser)
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
}
