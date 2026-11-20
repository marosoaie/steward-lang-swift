import Steward
import SwiftSyntax

/// A `func` declaration: in a type, an extension or a protocol, at the top
/// of a file, or inside another function or a closure.
///
/// Everything here is read from the syntax, so a return type is the type
/// as written: a typealias isn't resolved, and a function without `->`
/// has no return type, not `Void`.
///
/// The value isn't `Equatable`: two parses of the same text give
/// different nodes, and a body edit leaves everything else alike. Compare
/// `signature` for "declared alike", and the syntax for anything else.
/// Nor does it have a memberwise initializer: its properties come from
/// its node, and would disagree with it if they were set by hand. It
/// keeps the whole file's tree alive.
public struct FunctionDeclaration: Sendable {
    /// The name without its parameters, such as `load`, or the operator,
    /// such as `==`. An escaped name loses its backticks.
    public var name: String

    /// The access level, written out or not.
    public var access: AccessLevel

    /// Whether the function is `async`.
    public var isAsync: Bool

    /// Whether the function throws: `throws`, `throws(SomeError)` or
    /// `rethrows`.
    public var isThrowing: Bool

    /// Whether the function is `static` or `class`.
    public var isStatic: Bool

    /// The type after `->`, or nil when there is no `->`.
    public var returnType: TypeName?

    /// The parameters, in order.
    public var parameters: [Parameter]

    /// The attributes, in order, including those in each branch of an
    /// `#if` among them.
    public var attributes: [Attribute]

    /// The modifiers, in order, each spelled with no space or comment
    /// inside its parentheses: `override`, `mutating`,
    /// `nonisolated(nonsending)`. `access` and `isStatic` are typed views of
    /// some of them.
    public var modifiers: [String]

    /// The doc comment's text without its markers, read as the compiler
    /// reads it, or nil when there's none. It's the last run of `///` and
    /// `/** */` comments before the declaration: a blank line or a plain
    /// comment between it and the declaration doesn't detach it, but a
    /// blank line between two doc comments starts a new run, and a comment
    /// above an `#if` belongs to the `#if`. Line breaks stay; each line
    /// loses the indentation of the first non-empty one, and a block
    /// comment loses its ` * ` decoration when its `/**` ends a line and the
    /// stars line up under it. Blank lines at the start and the end are
    /// dropped, so an empty doc comment is `""`.
    ///
    /// Where the compiler, as of Swift 6.4, reads otherwise: a doc comment
    /// after code on the line above is no declaration's, where the compiler
    /// gives it to the next one; a block comment with CRLF line ends reads
    /// as one with LF ends, where the compiler keeps its stars and adds an
    /// empty line after each line; and in a decorated block comment, the
    /// star of a `**/` closer is decoration too, where the compiler keeps a
    /// ` *` line.
    public var documentation: String?

    /// The line of the function's name, to report a finding at.
    public var location: Location

    /// The lines from the first attribute or modifier, or the `func`
    /// keyword, to the closing brace, or the end of the signature for a
    /// protocol requirement. Comments before the declaration, such as its
    /// documentation, aren't part of it.
    public var lineRange: ClosedRange<Int>

    /// What the declaration says to callers, as data that compares.
    public var signature: FunctionSignature

    /// The declaration's syntax node. It follows swift-syntax's version,
    /// not this package's. Nodes are `Hashable` by identity: two parses of
    /// the same text give different nodes.
    public var syntax: FunctionDeclSyntax
}

extension FunctionDeclaration {
    init(_ function: FunctionDeclSyntax, path: String, lines: SourceLines) {
        let signature = FunctionSignature(
            function,
            access: AccessLevel(of: function, modifiers: function.modifiers),
            isStatic: function.modifiers.contains {
                $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
            }
        )
        name = signature.name
        access = signature.access
        isAsync = signature.isAsync
        isThrowing = signature.isThrowing
        isStatic = signature.isStatic
        returnType = signature.returnType
        parameters = function.signature.parameterClause.parameters.map { Parameter($0, path: path, lines: lines) }
        attributes = Attribute.all(in: function.attributes, path: path, lines: lines)
        modifiers = function.modifiers.map(\.normalizedSpelling)
        documentation = Documentation.text(of: function, lines: lines)
        location = Location(path: path, line: lines.line(of: function.name))
        lineRange = lines.lineRange(of: function)
        self.signature = signature
        syntax = function
    }
}
