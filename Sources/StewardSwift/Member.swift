import Steward
import SwiftSyntax

/// A member of a type or an extension, or a declaration at the top of a
/// file, as the source declares it: one for each name, so `var a, b: Int`
/// and `case a, b` are two each.
///
/// The value isn't `Equatable` and has no memberwise initializer, as
/// `TypeDeclaration` hasn't: it holds its declaration's node, and its
/// properties come from it.
public struct Member: Sendable {
    /// What a member declares.
    public enum Kind: String, Sendable, Hashable, CaseIterable, CustomStringConvertible {
        case function
        case initializer
        case deinitializer
        case `subscript`
        /// A `var` or a `let`, stored or computed.
        case property
        /// An enum's `case`.
        case `case`
        /// A nested struct, class, enum, actor or protocol.
        case type
        case typeAlias
        case associatedType
        /// A freestanding macro, such as `#warning(…)`.
        case macroExpansion
        /// A `macro` declaration, which valid Swift has only at the top of a
        /// file.
        case macro

        /// The kind, as a finding names it, such as `typeAlias`.
        public var description: String {
            rawValue
        }
    }

    /// What the member declares.
    public var kind: Kind

    /// The name: `init`, `deinit` and `subscript` for those kinds, and the
    /// macro's name, without `#`, for a macro expansion.
    public var name: String

    /// The access level, written out or not. An enum's cases and a
    /// deinitializer, which can't write one out, have their type's, but at
    /// least `internal`, as Swift gives them.
    public var access: AccessLevel

    /// The level the member is visible at: the lowest of `access` and the
    /// effective levels of the types around it in the file, or `private`
    /// inside a function or closure body or a `switch` case. So a `public`
    /// member of an `internal` struct is `internal`, a protocol's
    /// requirement and an enum's case have their type's level, and an
    /// `open` member of a `public` class is `public`, since the class can't
    /// be subclassed outside its module; but an `open` class nested in a
    /// `public` type stays `open`, as a client can subclass it. At the top
    /// of a file it's `access`'s level. An extension doesn't cap what it
    /// holds, since the type it extends may be declared in another file: a
    /// `public` member of an extension of an `internal` type is `public`
    /// here, and its block's `owner` is `.extension`. From `internal` up
    /// it's Swift's level but for that; below, it can be lower: a member of
    /// a `private` type at the top of a file is `fileprivate` to Swift.
    public var effectiveAccess: AccessLevel.Level

    /// Whether the member is `static` or `class`.
    public var isStatic: Bool

    /// Whether the member is inside an `#if` in its member block, or, at
    /// the top of a file, in the file. Every branch's members are read, in
    /// source order.
    public var isConditional: Bool

    /// The attributes, in order, with those in each branch of an `#if`:
    /// the declaration's, shared by the names it declares, so
    /// `@MainActor var a, b` gives both `MainActor`. A property wrapper is
    /// named as spelled, such as `Combine.Published`. Since the names share
    /// them, a check that reads every member's attributes does names ×
    /// attributes work on one declaration: quadratic in a file written to
    /// make it so (SECURITY.md).
    public var attributes: [Attribute]

    /// The modifiers, in order, each spelled with no space or comment
    /// inside its parentheses: `weak`, `lazy`, `override`, `private(set)`.
    /// They're the declaration's, shared by the names it declares, as its
    /// attributes are. `access` and `isStatic` are typed views of some of
    /// them.
    public var modifiers: [String]

    /// The doc comment's text, read as `FunctionDeclaration.documentation`
    /// is, or nil when there's none: the declaration's, shared by the names
    /// it declares, as its attributes are, at the same cost to a check that
    /// reads every member's (SECURITY.md).
    public var documentation: String?

    /// A property's details, as written: whether it's a `let`, whether it's
    /// stored, its type and its initial value. Nil for every other kind.
    public var property: Property?

    /// The line of the member's name, or of its keyword when it has no
    /// name.
    public var location: Location

    /// The lines of the whole declaration, shared by the names it declares,
    /// without the comments before it.
    public var lineRange: ClosedRange<Int>

    /// The declaration's syntax node, shared by the names it declares, as
    /// its attributes are: the two members of `var a, b: Int` hold one
    /// `VariableDeclSyntax`, and those of `case a, b` one
    /// `EnumCaseDeclSyntax`, so its `id` doesn't tell them apart. A name's
    /// own binding or case element is the one in the declaration's
    /// `bindings` or `elements` that holds the name, anywhere in its
    /// pattern, so `let (c, d) = pair`'s two names share a binding too.
    /// Match a token by its `identifier?.name`: `name` has no backticks,
    /// and a token's `text` keeps them. It follows swift-syntax's version,
    /// not this package's.
    public var syntax: DeclSyntax
}

extension Member {
    /// The declarations directly in `block`, with those in each branch of
    /// an `#if` among them, in source order, and whether each is in one.
    static func declarations(in block: MemberBlockSyntax) -> [(declaration: DeclSyntax, isConditional: Bool)] {
        block.preorder { node in
            node.is(MemberBlockSyntax.self) || node.is(MemberBlockItemListSyntax.self)
                || node.is(MemberBlockItemSyntax.self) || node.is(IfConfigDeclSyntax.self)
                || node.is(IfConfigClauseListSyntax.self) || node.is(IfConfigClauseSyntax.self)
        }
        .compactMap { $0.as(MemberBlockItemSyntax.self) }
        .map { item in
            let inBlock = item.ancestors.prefix { $0.id != block.id }
            return (item.decl, inBlock.contains { $0.is(IfConfigClauseSyntax.self) })
        }
    }

    /// The members that `item`'s declaration declares, one for each name.
    /// `owner` is the block it's in, or nil at the top of a file.
    static func all(
        in item: (declaration: DeclSyntax, isConditional: Bool),
        owner: MemberBlockSyntax?,
        path: String,
        lines: SourceLines,
        caps: AccessCaps
    ) -> [Member] {
        let (declaration, isConditional) = item
        let modifierList = declaration.asProtocol((any WithModifiersSyntax).self)?.modifiers ?? []
        let modifiers = modifierList.map(\.normalizedSpelling)
        let isStatic = modifierList.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        let access = if declaration.is(EnumCaseDeclSyntax.self) || declaration.is(DeinitializerDeclSyntax.self) {
            AccessLevel(implicitMemberOf: owner)
        } else if owner == nil, AccessLevel.Level(writtenIn: modifierList) == nil {
            // At the top of a file a level not written out is `internal`,
            // with no walk up through the `#if`s around it to find that.
            AccessLevel(level: .internal, isExplicit: false)
        } else {
            AccessLevel(of: declaration, modifiers: modifierList)
        }
        // A nested type's level is its own entry; at the top of a file
        // nothing caps a declaration.
        let effectiveAccess = caps.typeLevel(of: declaration)
            ?? owner.map { caps.effectiveLevel(in: $0, declared: access.level) } ?? access.level
        let attributes = declaration.asProtocol((any WithAttributesSyntax).self)
            .map { Attribute.all(in: $0.attributes, path: path, lines: lines) } ?? []
        let documentation = Documentation.text(of: declaration, lines: lines)
        let lineRange = lines.lineRange(of: declaration)
        return names(of: declaration).map { declared in
            Member(
                kind: declared.kind,
                name: declared.name,
                access: access,
                effectiveAccess: effectiveAccess,
                isStatic: isStatic,
                isConditional: isConditional,
                attributes: attributes,
                modifiers: modifiers,
                documentation: documentation,
                property: declared.property,
                location: Location(path: path, line: lines.line(of: declared.token)),
                lineRange: lineRange,
                syntax: declaration
            )
        }
    }

    /// A name a declaration declares, with its kind and the token to
    /// report it at.
    private struct DeclaredName {
        var kind: Kind
        var name: String
        var token: TokenSyntax
        var property: Property?
    }

    /// The kinds of the declarations that have a `name` token.
    private static let namedKinds: [SyntaxKind: Kind] = [
        .functionDecl: .function,
        .structDecl: .type,
        .classDecl: .type,
        .enumDecl: .type,
        .actorDecl: .type,
        .protocolDecl: .type,
        .typeAliasDecl: .typeAlias,
        .associatedTypeDecl: .associatedType,
        .macroDecl: .macro,
    ]

    /// Each name `declaration` declares.
    private static func names(of declaration: DeclSyntax) -> [DeclaredName] {
        if let kind = namedKinds[declaration.kind],
           let named = declaration.asProtocol((any NamedDeclSyntax).self) {
            return [DeclaredName(kind: kind, name: named.name.unescapedText, token: named.name)]
        }
        switch declaration.as(DeclSyntaxEnum.self) {
        case .initializerDecl(let initializer):
            return [DeclaredName(kind: .initializer, name: "init", token: initializer.initKeyword)]
        case .deinitializerDecl(let deinitializer):
            return [DeclaredName(kind: .deinitializer, name: "deinit", token: deinitializer.deinitKeyword)]
        case .subscriptDecl(let subscriptDecl):
            return [DeclaredName(kind: .subscript, name: "subscript", token: subscriptDecl.subscriptKeyword)]
        case .macroExpansionDecl(let macro):
            return [DeclaredName(kind: .macroExpansion, name: macro.macroName.unescapedText, token: macro.macroName)]
        case .variableDecl(let variable):
            return Property.all(in: variable).map { pattern, property in
                DeclaredName(
                    kind: .property,
                    name: pattern.identifier.unescapedText,
                    token: pattern.identifier,
                    property: property
                )
            }
        case .enumCaseDecl(let enumCase):
            return enumCase.elements.map { DeclaredName(kind: .case, name: $0.name.unescapedText, token: $0.name) }
        default:
            return []
        }
    }
}
