import Steward
import SwiftSyntax

/// The members of a type or an extension, between its braces, in source
/// order: what an ordering rule reads.
///
/// ```swift
/// // Private functions come last in their type or extension.
/// file.memberBlocks.flatMap { block in
///     block.functions.drop { $0.access.level != .private }.filter { $0.access.level != .private }
/// }
/// ```
///
/// The value isn't `Equatable` and has no memberwise initializer: it holds
/// its node, and its properties come from it.
public struct MemberBlock: Sendable {
    /// Whose members these are.
    public enum Owner: Sendable, Hashable, CustomStringConvertible {
        /// A type declaration's, of this kind and name.
        case type(TypeDeclaration.Kind, name: String)
        /// An extension's, of the type as it's spelled.
        case `extension`(TypeName)

        /// The owner as a finding names it, such as `struct Loader` or
        /// `extension Loader`.
        public var description: String {
            switch self {
            case .type(let kind, let name): "\(kind) \(name)"
            case .extension(let type): "extension \(type)"
            }
        }
    }

    /// The type or extension the block belongs to.
    public var owner: Owner

    /// The owner's access level: for an extension, the one it writes out,
    /// or `internal`. A `private extension` is `private` here, while its
    /// members default to `fileprivate`, as Swift gives them. A block has
    /// no `effectiveAccess`: a type's is its `TypeDeclaration`'s, and each
    /// member has its own.
    public var access: AccessLevel

    /// The owner's inherited types, as spelled: a type's, or the
    /// conformances an extension adds, such as `@unchecked Sendable` in
    /// `extension Cache: @unchecked Sendable {}`.
    public var inheritedTypes: [TypeName]

    /// The owner's attributes, in order, with those in each branch of an
    /// `#if`: a type's, or an extension's.
    public var attributes: [Attribute]

    /// The owner's doc comment's text, a type's or an extension's, read as
    /// `FunctionDeclaration.documentation` is, or nil when there's none.
    public var documentation: String?

    /// The members, in source order, with those in each branch of an `#if`
    /// marked as conditional.
    public var members: [Member]

    /// The members that are `func` declarations, in source order. Functions
    /// in members' bodies aren't among them.
    public var functions: [FunctionDeclaration]

    /// The line of the owner's name, or of the extended type.
    public var location: Location

    /// The owner's lines, from its first attribute or modifier to its
    /// closing brace.
    public var lineRange: ClosedRange<Int>

    /// The block's syntax node; its parent is the owner's declaration. It
    /// follows swift-syntax's version, not this package's.
    public var syntax: MemberBlockSyntax
}

extension MemberBlock {
    /// The block of a type or an extension declaration, or nil for any
    /// other node.
    init?(_ block: MemberBlockSyntax, path: String, lines: SourceLines, caps: AccessCaps) {
        guard let parent = block.parent?.as(DeclSyntax.self),
              let group = parent.asProtocol((any DeclGroupSyntax).self)
        else { return nil }
        if let type = TypeDeclaration(parent, path: path, lines: lines, caps: caps) {
            owner = .type(type.kind, name: type.name)
            location = type.location
            members = type.members
        } else if let extensionDecl = parent.as(ExtensionDeclSyntax.self) {
            owner = .extension(TypeName(extensionDecl.extendedType))
            location = Location(path: path, line: lines.line(of: extensionDecl.extendedType))
            members = Member.declarations(in: block).flatMap { member in
                Member.all(
                    in: member,
                    owner: block,
                    path: path,
                    lines: lines,
                    caps: caps
                )
            }
        } else {
            return nil
        }
        access = AccessLevel(of: parent, modifiers: group.modifiers)
        inheritedTypes = group.inheritanceClause?.inheritedTypes.map { TypeName($0.type) } ?? []
        attributes = Attribute.all(in: group.attributes, path: path, lines: lines)
        documentation = Documentation.text(of: parent, lines: lines)
        functions = Member.declarations(in: block)
            .compactMap { $0.declaration.as(FunctionDeclSyntax.self) }
            .map { FunctionDeclaration($0, path: path, lines: lines, caps: caps) }
        lineRange = lines.lineRange(of: parent)
        syntax = block
    }
}
