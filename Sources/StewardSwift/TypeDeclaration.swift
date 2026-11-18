import Steward
import SwiftSyntax

/// A struct, class, enum, actor or protocol declaration, at any depth:
/// at the top of a file, nested in another type or an extension, or local
/// to a function.
///
/// The value isn't `Equatable` and has no memberwise initializer, as
/// `FunctionDeclaration` hasn't: it holds its node, and its properties come
/// from it.
public struct TypeDeclaration: Sendable {
    /// Which kind of type the declaration declares.
    public enum Kind: String, Sendable, Hashable, CaseIterable, CustomStringConvertible {
        case `struct`
        case `class`
        case `enum`
        case actor
        case `protocol`

        /// The keyword, such as `struct`.
        public var description: String {
            rawValue
        }
    }

    /// The kind.
    public var kind: Kind

    /// The name. An escaped name loses its backticks.
    public var name: String

    /// The access level, written out or not.
    public var access: AccessLevel

    /// The types after the colon, in order and as spelled: superclass,
    /// protocols, a raw value type, `@unchecked Sendable`.
    public var inheritedTypes: [TypeName]

    /// The attributes, in order, with those in each branch of an `#if`.
    public var attributes: [Attribute]

    /// The members of the type's own block, in source order, with those in
    /// each branch of an `#if` marked as conditional. An extension's members
    /// are in `SwiftFile.memberBlocks`.
    public var members: [Member]

    /// The line of the type's name.
    public var location: Location

    /// The lines from the first attribute or modifier, or the keyword, to
    /// the closing brace, without the comments before them.
    public var lines: ClosedRange<Int>

    /// The declaration's syntax node: a `StructDeclSyntax`,
    /// `ClassDeclSyntax`, `EnumDeclSyntax`, `ActorDeclSyntax` or
    /// `ProtocolDeclSyntax`. It follows swift-syntax's version, not this
    /// package's.
    public var syntax: DeclSyntax
}

extension TypeDeclaration {
    /// The type `declaration` declares, or nil when it doesn't declare one.
    init?(_ declaration: DeclSyntax, path: String, lines: SourceLines) {
        let kind: Kind
        switch declaration.as(DeclSyntaxEnum.self) {
        case .structDecl: kind = .struct
        case .classDecl: kind = .class
        case .enumDecl: kind = .enum
        case .actorDecl: kind = .actor
        case .protocolDecl: kind = .protocol
        default: return nil
        }
        guard let group = declaration.asProtocol((any DeclGroupSyntax).self),
              let named = declaration.asProtocol((any NamedDeclSyntax).self)
        else { return nil }
        self.kind = kind
        name = named.name.unescapedText
        access = AccessLevel(of: declaration, modifiers: group.modifiers)
        inheritedTypes = group.inheritanceClause?.inheritedTypes.map { TypeName($0.type) } ?? []
        attributes = Attribute.all(in: group.attributes, path: path, lines: lines)
        members = Member.declarations(in: group.memberBlock).flatMap { member in
            Member.all(
                in: member.declaration,
                isConditional: member.isConditional,
                owner: group.memberBlock,
                path: path,
                lines: lines
            )
        }
        location = Location(path: path, line: lines.line(of: named.name))
        self.lines = lines.lines(of: declaration)
        syntax = declaration
    }
}
