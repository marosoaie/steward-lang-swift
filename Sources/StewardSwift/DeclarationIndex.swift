import SwiftSyntax

/// A file's units, for `SwiftSourceScope`: the declarations the model
/// names and the file's top-level statements, the lines each spans, which
/// holds which, and for a type or an extension, the lines inside its
/// braces.
///
/// A unit is a type or an extension, a member of one, a `func` at any
/// depth, or a declaration or statement at the top of the file, each
/// through any `#if` around it. A local `let`, an accessor or a closure
/// isn't one: its lines belong to the unit around it.
struct DeclarationIndex: Sendable {
    struct Unit: Sendable {
        /// From the comment lines directly above the unit, with no blank
        /// line between, to its last token.
        var lines: ClosedRange<Int>
        /// For a type or an extension, the lines inside its braces, from
        /// the one after the line of `{` to the line of `}`; nil for any
        /// other unit, and for braces with no line between them.
        var body: ClosedRange<Int>?
        /// Its lines up to the last of its names' and of its `{`s', if it
        /// has them: they are its own, whatever else starts on them.
        var header: ClosedRange<Int>
        /// The innermost unit around this one.
        var parent: Int?
    }

    /// In source order, outer before inner, so in order of their first
    /// lines.
    let units: [Unit]

    init(file: SwiftFile) {
        // The item lists at the top of the file, through any `#if`, found
        // once from the root, so that telling whether an item is at the top
        // costs the same however deep the `#if`s around it nest.
        let topLevel = Set(file.syntax.preorder { node in
            node.is(SourceFileSyntax.self) || node.is(CodeBlockItemListSyntax.self)
                || node.is(CodeBlockItemSyntax.self) || node.is(IfConfigDeclSyntax.self)
                || node.is(IfConfigClauseListSyntax.self) || node.is(IfConfigClauseSyntax.self)
        }.filter { $0.is(CodeBlockItemListSyntax.self) }.map(\.id))
        let nodes = file.syntax.preorder().filter { Self.isUnit($0, topLevel: topLevel) }
        units = Self.units(nodes, lines: file.sourceLines)
    }

    /// The innermost unit whose lines hold `line`, if one does.
    ///
    /// The last unit to start at or before the line is inside the innermost
    /// one that holds it, or is it, since units nest, so the answer is the
    /// first of its ancestors that holds the line: a binary search, and a
    /// walk as long as the nesting is deep.
    func innermost(containing line: Int) -> Int? {
        // A binary search, for the last unit that starts at or before `line`.
        var low = 0
        var high = units.count
        while low < high {
            let middle = low + (high - low) / 2
            if units[middle].lines.lowerBound <= line {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return nil }
        return sequence(first: low - 1) { units[$0].parent }.first { units[$0].lines.contains(line) }
    }

    /// `unit`, or the outermost unit around it whose header holds `line`:
    /// a declaration's lines up to its name and its `{` are its own, so a
    /// member that starts on its type's `{` line, or a local function on
    /// a property's, doesn't take the line from it.
    func owner(of unit: Int, line: Int) -> Int {
        sequence(first: unit) { units[$0].parent }.dropFirst()
            .prefix { units[$0].header.contains(line) }
            .reduce(unit) { $1 }
    }

    /// The type or extension whose braces hold `line` most closely, among
    /// `unit` and the units around it.
    func container(of unit: Int, line: Int) -> Int? {
        sequence(first: unit) { units[$0].parent }.first { units[$0].body?.contains(line) == true }
    }

    /// Whether `node` is a unit, given the item lists at the top of the
    /// file.
    private static func isUnit(_ node: Syntax, topLevel: Set<SyntaxIdentifier>) -> Bool {
        // An item of a list at the top of the file.
        let isTopLevel = node.parent?.is(CodeBlockItemSyntax.self) == true
            && node.parent?.parent.map { topLevel.contains($0.id) } == true
        guard let declaration = node.as(DeclSyntax.self) else {
            return (node.is(StmtSyntax.self) || node.is(ExprSyntax.self)) && isTopLevel
        }
        return !declaration.is(IfConfigDeclSyntax.self) && (
            declaration.is(FunctionDeclSyntax.self) || declaration.isProtocol((any DeclGroupSyntax).self)
                || node.parent?.is(MemberBlockItemSyntax.self) == true || isTopLevel
        )
    }

    /// The units of `nodes`, in source order, each with its parent: the last
    /// one still open at its start, since units nest by their bytes, which
    /// two on one line don't by their lines.
    private static func units(_ nodes: [Syntax], lines: SourceLines) -> [Unit] {
        // An imperative loop: the stack of units still open is the state
        // carried from one unit to the next.
        var open: [(index: Int, end: Int)] = []
        var units: [Unit] = []
        for node in nodes {
            let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
            while let last = open.last, last.end <= start {
                open.removeLast()
            }
            let commented = commentedLines(of: node, in: lines)
            units.append(Unit(
                lines: commented,
                body: body(of: node, in: lines),
                header: commented.lowerBound...headerEnd(of: node, in: lines),
                parent: open.last?.index
            ))
            open.append((units.count - 1, node.endPositionBeforeTrailingTrivia.utf8Offset))
        }
        return units
    }

    /// The lines of `node`, from the comments directly above it, its doc
    /// comment among them, to its last token: a pull request that edits
    /// only a doc comment changes what it documents.
    private static func commentedLines(of node: Syntax, in lines: SourceLines) -> ClosedRange<Int> {
        let tokens = lines.lines(of: node)
        // Back from the first token: comments, separated by one line break
        // at most, and the spaces around them.
        var offset = node.positionAfterSkippingLeadingTrivia.utf8Offset
        var firstComment: Int?
        var breaks = 0
        for piece in node.leadingTrivia.pieces.reversed() {
            offset -= piece.sourceLength.utf8Length
            if piece.isComment {
                firstComment = offset
                breaks = 0
                continue
            }
            switch piece {
            case .spaces, .tabs, .verticalTabs, .formfeeds, .carriageReturns:
                continue
            case .newlines(let count), .carriageReturnLineFeeds(let count):
                breaks += count
            default:
                breaks = 2
            }
            if breaks > 1 {
                break
            }
        }
        return firstComment.map { lines.line(atUTF8Offset: $0)...tokens.upperBound } ?? tokens
    }

    /// The last line of `node`'s header: the latest of its first token's,
    /// the last line of each name it declares, and its `{`s'.
    private static func headerEnd(of node: Syntax, in lines: SourceLines) -> Int {
        let marks = names(of: node).map { lines.lines(of: $0).upperBound }
            + openingBraces(of: node).map { lines.line(of: $0) }
        return ([lines.line(of: node)] + marks).max() ?? lines.line(of: node)
    }

    /// The tokens and patterns that name what the declaration `node`
    /// declares: every binding's pattern, tuples included, for a property.
    private static func names(of node: Syntax) -> [Syntax] {
        if let named = node.asProtocol((any NamedDeclSyntax).self) {
            return [Syntax(named.name)]
        }
        return switch node.as(SyntaxEnum.self) {
        case .variableDecl(let variable): variable.bindings.map { Syntax($0.pattern) }
        case .enumCaseDecl(let enumCase): enumCase.elements.map { Syntax($0.name) }
        case .initializerDecl(let initializer): [Syntax(initializer.initKeyword)]
        case .deinitializerDecl(let deinitializer): [Syntax(deinitializer.deinitKeyword)]
        case .subscriptDecl(let subscriptDecl): [Syntax(subscriptDecl.subscriptKeyword)]
        case .extensionDecl(let extensionDecl): [Syntax(extensionDecl.extendedType)]
        default: []
        }
    }

    /// The `{`s that open `node`'s members, body or accessors.
    private static func openingBraces(of node: Syntax) -> [TokenSyntax] {
        if let group = node.asProtocol((any DeclGroupSyntax).self) {
            return [group.memberBlock.leftBrace]
        }
        return switch node.as(SyntaxEnum.self) {
        case .functionDecl(let function): [function.body?.leftBrace].compactMap(\.self)
        case .initializerDecl(let initializer): [initializer.body?.leftBrace].compactMap(\.self)
        case .deinitializerDecl(let deinitializer): [deinitializer.body?.leftBrace].compactMap(\.self)
        case .subscriptDecl(let subscriptDecl): [subscriptDecl.accessorBlock?.leftBrace].compactMap(\.self)
        case .variableDecl(let variable): variable.bindings.compactMap { $0.accessorBlock?.leftBrace }
        default: []
        }
    }

    /// For a type or an extension, the lines inside its braces.
    private static func body(of node: Syntax, in lines: SourceLines) -> ClosedRange<Int>? {
        guard let group = node.asProtocol((any DeclGroupSyntax).self) else { return nil }
        let first = lines.line(of: group.memberBlock.leftBrace) + 1
        let last = lines.line(of: group.memberBlock.rightBrace)
        return first <= last ? first...last : nil
    }
}
