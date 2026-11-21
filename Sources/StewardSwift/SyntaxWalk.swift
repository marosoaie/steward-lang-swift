import SwiftSyntax

// Walks over syntax trees that don't recurse. A pull request controls the
// source, and swift-syntax's own walks (`SyntaxVisitor`, `firstToken`,
// `description`) recurse once per level of the tree, which a long postfix
// chain makes as deep as the file is long.

extension SyntaxProtocol {
    /// The node's ancestors, from its parent up to the root.
    var ancestors: some Sequence<Syntax> {
        sequence(first: Syntax(self), next: \.parent).dropFirst()
    }

    /// The node and its descendants in source order, as the source writes
    /// them: tokens the parser made up to repair the source are left out,
    /// and text it couldn't place is kept.
    ///
    /// `descend` decides whether to walk into a node's children; the node
    /// itself is part of the walk either way.
    func preorder(descendingInto descend: @escaping (Syntax) -> Bool = { _ in true }) -> PreorderWalk {
        PreorderWalk(root: Syntax(self), descend: descend)
    }

    /// The depth of the tree under this node, counting the node as 1, or
    /// `cap` once it reaches `cap`, so a deep tree isn't walked in full.
    func depth(cappedAt cap: Int) -> Int {
        // An imperative loop: the stack of nodes and their depths is the
        // walk's state, and the walk stops as soon as it reaches the cap.
        var pending = [(Syntax(self), 1)]
        var deepest = 0
        while let (node, depth) = pending.popLast(), deepest < cap {
            deepest = Swift.max(deepest, depth)
            pending.append(contentsOf: node.children(viewMode: .sourceAccurate).lazy.map { ($0, depth + 1) })
        }
        return Swift.min(deepest, cap)
    }

    /// The tokens' text as the source writes it, without comments, and
    /// with one space wherever trivia separates two tokens, but none around
    /// the `.` or `::` of a qualified name: `Combine .Published` is spelled
    /// `Combine.Published`. Escaped identifiers lose their backticks.
    var spelling: String {
        let tokens = preorder().compactMap { $0.as(TokenSyntax.self) }
        let pieces = zip([nil] + tokens.map(Optional.some), tokens).map { previous, token in
            let separated = previous.map {
                (!$0.trailingTrivia.isEmpty || !token.leadingTrivia.isEmpty)
                    && !$0.isQualifier && !token.isQualifier
            } ?? false
            return (separated ? " " : "") + token.unescapedText
        }
        return pieces.joined()
    }
}

extension TokenSyntax {
    /// The token's text, without backticks if it's an escaped identifier.
    var unescapedText: String {
        identifier?.name ?? text
    }

    /// Whether the token joins the parts of a qualified name: the dot of a
    /// member type, such as `Combine.Published`, of a metatype, such as
    /// `Int.Type`, or of an import path, such as `Foundation.Data`, or a
    /// module selector's `::`, such as `Swift::Int`. A member access's dot,
    /// as in `.long`, isn't one.
    var isQualifier: Bool {
        let isDot = parent?.as(MemberTypeSyntax.self)?.period.id == id
            || parent?.as(MetatypeTypeSyntax.self)?.period.id == id
            || parent?.as(ImportPathComponentSyntax.self)?.trailingPeriod?.id == id
        #if canImport(SwiftSyntax603)
        // Module selectors came with swift-syntax 603; 602 has no `::`.
        return isDot || parent?.as(ModuleSelectorSyntax.self)?.colonColon.id == id
        #else
        return isDot
        #endif
    }
}

extension SourceFileSyntax {
    /// The file's top level, in source order: its item lists and their
    /// items, through any `#if`, and what each item holds, without going
    /// into a declaration, a statement or an expression.
    var topLevel: PreorderWalk {
        preorder { node in
            node.is(SourceFileSyntax.self) || node.is(CodeBlockItemListSyntax.self)
                || node.is(CodeBlockItemSyntax.self) || node.is(IfConfigDeclSyntax.self)
                || node.is(IfConfigClauseListSyntax.self) || node.is(IfConfigClauseSyntax.self)
        }
    }
}

/// A depth-first walk over a syntax tree that keeps its own stack, so a
/// tree of any depth is walked in constant call depth.
struct PreorderWalk: Sequence, IteratorProtocol {
    private var pending: [Syntax]
    private let descend: (Syntax) -> Bool

    init(root: Syntax, descend: @escaping (Syntax) -> Bool) {
        pending = [root]
        self.descend = descend
    }

    mutating func next() -> Syntax? {
        guard let node = pending.popLast() else { return nil }
        if descend(node) {
            // Reversed, so that the first child is popped first.
            pending.append(contentsOf: node.children(viewMode: .sourceAccurate).reversed())
        }
        return node
    }
}
