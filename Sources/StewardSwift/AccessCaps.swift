import SwiftSyntax

/// What the declarations around a node cap its access level at, for
/// `effectiveAccess`: the nearest struct, class, enum, actor or protocol
/// around it, at that type's own effective level, or a function, closure or
/// accessor body, at `private`, whichever comes first going up. An
/// extension doesn't cap what it holds, since the type it extends may be
/// declared in another file, and the top of a file caps nothing. A
/// `public` type caps what's inside it at `public`, but an `open` class
/// nested in one stays `open`: being nested limits where the class is
/// seen, not whether a client can subclass it.
struct AccessCaps: Sendable {
    /// Each type declaration's effective level, by its node.
    private let typeLevels: [SyntaxIdentifier: AccessLevel.Level]

    /// The item lists at the top of the file, through any `#if`: a walk up
    /// that reaches one ends there, with no cap, rather than at the root.
    private let topLevelLists: Set<SyntaxIdentifier>

    /// The caps of `tree`, whose nodes are `nodes`, in preorder: a type
    /// comes before the types inside it, so its level is known by the time
    /// theirs is worked out, and each type's is one short walk up.
    init(tree: SourceFileSyntax, nodes: [Syntax]) {
        let topLevelLists = Set(tree.topLevel.filter { $0.kind == .codeBlockItemList }.map(\.id))
        self.topLevelLists = topLevelLists
        typeLevels = nodes.reduce(into: [:]) { levels, node in
            guard Self.isType(node.kind), let group = node.asProtocol((any DeclGroupSyntax).self) else { return }
            let declared = Self.accessLevel(of: node, modifiers: group.modifiers, topLevelLists: topLevelLists).level
            let cap = Self.cap(around: node, typeLevels: levels, topLevelLists: topLevelLists)
            levels[node.id] = declared == .open && cap == .public ? .open : Swift.min(declared, cap)
        }
    }

    /// The access level of `declaration`, whose modifiers are `modifiers`,
    /// as `AccessLevel(of:modifiers:)` reads it, but with no walk up to the
    /// root for a level that isn't written out at the top of the file,
    /// which is `internal`.
    func accessLevel(of declaration: some SyntaxProtocol, modifiers: DeclModifierListSyntax) -> AccessLevel {
        Self.accessLevel(of: declaration, modifiers: modifiers, topLevelLists: topLevelLists)
    }

    /// `declared`, the level of the declaration `node`, capped by what's
    /// around it.
    func effectiveLevel(of node: some SyntaxProtocol, declared: AccessLevel.Level) -> AccessLevel.Level {
        Swift.min(declared, Self.cap(around: node, typeLevels: typeLevels, topLevelLists: topLevelLists))
    }

    /// `declared`, the level of a declaration directly in `block`, capped
    /// by the block's owner: a type, at its effective level, or an
    /// extension, by what's around it. No walk from the declaration up
    /// through the `#if`s around it in the block.
    func effectiveLevel(in block: MemberBlockSyntax, declared: AccessLevel.Level) -> AccessLevel.Level {
        guard let owner = block.parent else { return declared }
        let cap = typeLevels[owner.id] ?? Self.cap(around: owner, typeLevels: typeLevels, topLevelLists: topLevelLists)
        return Swift.min(declared, cap)
    }

    /// The effective level of `declaration` if it declares a struct,
    /// class, enum, actor or protocol, or nil.
    func typeLevel(of declaration: some SyntaxProtocol) -> AccessLevel.Level? {
        typeLevels[declaration.id]
    }

    /// The cap of the nearest type or body around `node`, or `open` when
    /// there's none.
    private static func cap(
        around node: some SyntaxProtocol,
        typeLevels: [SyntaxIdentifier: AccessLevel.Level],
        topLevelLists: Set<SyntaxIdentifier>
    ) -> AccessLevel.Level {
        // `first(where:)` stops at the nearest one: a `compactMap` with
        // `.first` would build the whole list of ancestors to the root.
        let nearest = node.ancestors.first { ancestor in
            switch ancestor.kind {
            case .codeBlockItemList: topLevelLists.contains(ancestor.id)
            case .codeBlock, .closureExpr, .accessorBlock: true
            default: isType(ancestor.kind)
            }
        }
        return switch nearest?.kind {
        case nil, .codeBlockItemList: .open
        case .codeBlock, .closureExpr, .accessorBlock: .private
        default: nearest.flatMap { typeLevels[$0.id] } ?? .open
        }
    }

    private static func accessLevel(
        of declaration: some SyntaxProtocol,
        modifiers: DeclModifierListSyntax,
        topLevelLists: Set<SyntaxIdentifier>
    ) -> AccessLevel {
        // A declaration's item list is its parent's parent.
        if AccessLevel.Level(writtenIn: modifiers) == nil, let list = declaration.parent?.parent,
           topLevelLists.contains(list.id) {
            return AccessLevel(level: .internal, isExplicit: false)
        }
        return AccessLevel(of: declaration, modifiers: modifiers)
    }

    /// Whether a node of `kind` declares a struct, class, enum, actor or
    /// protocol.
    private static func isType(_ kind: SyntaxKind) -> Bool {
        switch kind {
        case .structDecl, .classDecl, .enumDecl, .actorDecl, .protocolDecl: true
        default: false
        }
    }
}
