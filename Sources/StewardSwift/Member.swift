import Steward
import SwiftSyntax

/// A member of a type or an extension, as the source declares it: one for
/// each name, so `var a, b: Int` and `case a, b` are two each.
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

    /// Whether the member is `static` or `class`.
    public var isStatic: Bool

    /// Whether the member is inside an `#if` in its member block. Every
    /// branch's members are read, in source order.
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
    /// `bindings` or `elements` that holds the name. It follows
    /// swift-syntax's version, not this package's.
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

    /// The members `declaration` declares, one for each name.
    static func all(
        in declaration: DeclSyntax,
        isConditional: Bool,
        owner: MemberBlockSyntax,
        path: String,
        lines: SourceLines
    ) -> [Member] {
        let modifierList = declaration.asProtocol((any WithModifiersSyntax).self)?.modifiers ?? []
        let modifiers = modifierList.map(\.normalizedSpelling)
        let isStatic = modifierList.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        let access = declaration.is(EnumCaseDeclSyntax.self) || declaration.is(DeinitializerDeclSyntax.self)
            ? AccessLevel(implicitMemberOf: owner)
            : AccessLevel(of: declaration, modifiers: modifierList)
        let attributes = declaration.asProtocol((any WithAttributesSyntax).self)
            .map { Attribute.all(in: $0.attributes, path: path, lines: lines) } ?? []
        let documentation = Documentation.text(of: declaration, lines: lines)
        let lineRange = lines.lineRange(of: declaration)
        return names(of: declaration).map { declared in
            Member(
                kind: declared.kind,
                name: declared.name,
                access: access,
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
