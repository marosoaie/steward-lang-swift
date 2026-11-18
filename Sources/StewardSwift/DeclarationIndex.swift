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
        /// The innermost unit around this one.
        var parent: Int?
    }

    /// In source order, outer before inner, so in order of their first
    /// lines.
    let units: [Unit]

    init(file: SwiftFile) {
        let lines = file.sourceLines
        units = Self.units(file.syntax.preorder().filter(Self.isUnit), lines: lines)
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

    /// The type or extension whose braces hold `line` most closely, among
    /// `unit` and the units around it.
    func container(of unit: Int, line: Int) -> Int? {
        sequence(first: unit) { units[$0].parent }.first { units[$0].body?.contains(line) == true }
    }

    private static func isUnit(_ node: Syntax) -> Bool {
        guard let declaration = node.as(DeclSyntax.self) else {
            return (node.is(StmtSyntax.self) || node.is(ExprSyntax.self)) && isTopLevel(node)
        }
        return !declaration.is(IfConfigDeclSyntax.self) && (
            declaration.is(FunctionDeclSyntax.self) || declaration.isProtocol((any DeclGroupSyntax).self)
                || node.parent?.is(MemberBlockItemSyntax.self) == true || isTopLevel(node)
        )
    }

    /// Whether `node` is an item at the top of the file, through any `#if`.
    private static func isTopLevel(_ node: Syntax) -> Bool {
        guard let item = node.parent, item.is(CodeBlockItemSyntax.self) else { return false }
        let container = item.ancestors.first { ancestor in
            !(ancestor.is(CodeBlockItemListSyntax.self) || ancestor.is(CodeBlockItemSyntax.self)
                || ancestor.is(IfConfigClauseSyntax.self) || ancestor.is(IfConfigClauseListSyntax.self)
                || ancestor.is(IfConfigDeclSyntax.self))
        }
        return container?.is(SourceFileSyntax.self) == true
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
            units.append(Unit(
                lines: commentedLines(of: node, in: lines),
                body: body(of: node, in: lines),
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

    /// For a type or an extension, the lines inside its braces.
    private static func body(of node: Syntax, in lines: SourceLines) -> ClosedRange<Int>? {
        guard let group = node.asProtocol((any DeclGroupSyntax).self) else { return nil }
        let first = lines.line(of: group.memberBlock.leftBrace) + 1
        let last = lines.line(of: group.memberBlock.rightBrace)
        return first <= last ? first...last : nil
    }
}
