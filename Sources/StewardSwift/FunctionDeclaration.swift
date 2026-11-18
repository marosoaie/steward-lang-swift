import Steward
import SwiftSyntax

/// A `func` declaration: in a type, an extension or a protocol, at the top
/// of a file, or inside another function or a closure.
///
/// Everything here is read from the syntax, so a return type is the type
/// as written: a typealias isn't resolved, and a function without `->`
/// has no return type, not `Void`.
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

    /// The line of the function's name, to report a finding at.
    public var location: Location

    /// The lines from the first attribute or modifier, or the `func`
    /// keyword, to the closing brace, or the end of the signature for a
    /// protocol requirement. Comments before the declaration, such as its
    /// documentation, aren't part of it.
    public var lines: ClosedRange<Int>

    /// The declaration's syntax node. It follows swift-syntax's version,
    /// not this package's.
    public var syntax: FunctionDeclSyntax
}

extension FunctionDeclaration {
    init(_ function: FunctionDeclSyntax, path: String, lines: SourceLines) {
        let effects = function.signature.effectSpecifiers
        self.init(
            name: function.name.unescapedText,
            access: AccessLevel(of: function, modifiers: function.modifiers),
            isAsync: effects?.asyncSpecifier != nil,
            isThrowing: effects?.throwsClause != nil,
            isStatic: function.modifiers.contains {
                $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
            },
            returnType: function.signature.returnClause.map { TypeName($0.type) },
            parameters: function.signature.parameterClause.parameters.map {
                Parameter($0, path: path, lines: lines)
            },
            attributes: Attribute.all(in: function.attributes, path: path, lines: lines),
            location: Location(path: path, line: lines.line(of: function.name)),
            lines: lines.lines(of: function),
            syntax: function
        )
    }
}
