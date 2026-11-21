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

    /// The level the type is visible at: the lowest of `access` and the
    /// effective levels of the types around it in the file, or `private`
    /// inside a function or closure body, so a `public` type nested in an
    /// `internal` one is `internal`. An `open` class nested in a `public`
    /// type stays `open`, though: being nested limits where it's seen, not
    /// whether a client can subclass it. An extension doesn't cap what it
    /// holds, since the type it extends may be declared in another file: a
    /// type nested in an extension is capped only by what's around the
    /// extension. From `internal` up it's Swift's level but for that;
    /// below, it can be lower: a type nested in a `private` one at the top
    /// of a file is `fileprivate` to Swift.
    public var effectiveAccess: AccessLevel.Level

    /// Whether the type is `final`. The other modifiers, such as
    /// `indirect`, are in `modifiers`.
    public var isFinal: Bool

    /// The types after the colon, in order and as spelled: superclass,
    /// protocols, a raw value type, `@unchecked Sendable`.
    public var inheritedTypes: [TypeName]

    /// The attributes, in order, with those in each branch of an `#if`.
    public var attributes: [Attribute]

    /// The modifiers, in order, each spelled with no space or comment
    /// inside its parentheses: `public`, `final`, `indirect`,
    /// `nonisolated`. `access` and `isFinal` are typed views of some of
    /// them.
    public var modifiers: [String]

    /// The doc comment's text, read as `FunctionDeclaration.documentation`
    /// is, or nil when there's none.
    public var documentation: String?

    /// The members of the type's own block, in source order, with those in
    /// each branch of an `#if` marked as conditional. An extension's members
    /// are in `SwiftFile.memberBlocks`.
    public var members: [Member]

    /// The line of the type's name.
    public var location: Location

    /// The lines from the first attribute or modifier, or the keyword, to
    /// the closing brace, without the comments before them.
    public var lineRange: ClosedRange<Int>

    /// The declaration's syntax node: a `StructDeclSyntax`,
    /// `ClassDeclSyntax`, `EnumDeclSyntax`, `ActorDeclSyntax` or
    /// `ProtocolDeclSyntax`. It follows swift-syntax's version, not this
    /// package's.
    public var syntax: DeclSyntax
}

extension TypeDeclaration {
    /// The type `declaration` declares, or nil when it doesn't declare one.
    init?(_ declaration: DeclSyntax, path: String, lines: SourceLines, caps: AccessCaps) {
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
        access = caps.accessLevel(of: declaration, modifiers: group.modifiers)
        effectiveAccess = caps.typeLevel(of: declaration)
            ?? caps.effectiveLevel(of: declaration, declared: access.level)
        isFinal = group.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
        inheritedTypes = group.inheritanceClause?.inheritedTypes.map { TypeName($0.type) } ?? []
        attributes = Attribute.all(in: group.attributes, path: path, lines: lines)
        modifiers = group.modifiers.map(\.normalizedSpelling)
        documentation = Documentation.text(of: declaration, lines: lines)
        members = Member.declarations(in: group.memberBlock).flatMap { member in
            Member.all(
                in: member,
                owner: group.memberBlock,
                path: path,
                lines: lines,
                caps: caps
            )
        }
        location = Location(path: path, line: lines.line(of: named.name))
        lineRange = lines.lineRange(of: declaration)
        syntax = declaration
    }
}
