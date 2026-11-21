import SwiftSyntax

/// A file's units, for `SwiftSourceScope`: the declarations the model
/// names and the file's top-level statements, the lines each spans, which
/// holds which, for a type or an extension the lines inside its braces,
/// and which units have tokens of their own on each line.
///
/// A unit is a type or an extension, a member of one, a `func` at any
/// depth, or a declaration or statement at the top of the file, each
/// through any `#if` around it. A local `let`, an accessor or a closure
/// isn't one: its tokens and lines belong to the unit around it.
struct DeclarationIndex: Sendable {
    struct Unit: Sendable {
        /// From the comment lines directly above the unit, with no blank
        /// line between, to its last token.
        var lineRange: ClosedRange<Int>
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
    /// For each line, the units with a token of their own on it, not one
    /// of a unit inside them, in source order.
    private let owners: [[Int]]

    init(file: SwiftFile) {
        // The item lists at the top of the file, through any `#if`, found
        // once from the root, so that telling whether an item is at the top
        // costs the same however deep the `#if`s around it nest.
        let topLevel = Set(file.syntax.topLevel.filter { $0.is(CodeBlockItemListSyntax.self) }.map(\.id))
        (units, owners) = Self.index(file.syntax, lines: file.sourceLines, topLevel: topLevel)
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
            if units[middle].lineRange.lowerBound <= line {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low > 0 else { return nil }
        return sequence(first: low - 1) { units[$0].parent }.first { units[$0].lineRange.contains(line) }
    }

    /// The units a finding at `line` is judged by: every unit with a token
    /// of its own on the line, so that a line that two declarations share,
    /// `struct B { var x = 1` or `func a() {}; func b() {}`, is each one's;
    /// on a line with none, a blank or comment one, the innermost unit
    /// around it; at the top of the file, none.
    func units(judging line: Int) -> [Int] {
        let owning = owners.indices.contains(line) ? owners[line] : []
        guard owning.isEmpty else { return owning }
        return innermost(containing: line).map { [$0] } ?? []
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

    /// The units under `root`, in source order, each with its parent, and
    /// for each line the units with tokens of their own on it: in one walk,
    /// whose state is the stack of units still open, since units nest by
    /// their bytes, which two on one line don't by their lines.
    private static func index(
        _ root: SourceFileSyntax,
        lines: SourceLines,
        topLevel: Set<SyntaxIdentifier>
    ) -> (units: [Unit], owners: [[Int]]) {
        // An imperative loop: the stack of units still open is the state
        // carried from one node to the next.
        var open: [(index: Int, end: Int)] = []
        var units: [Unit] = []
        var owners = Array(repeating: [Int](), count: lines.count + 1)
        for node in root.preorder() {
            let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
            while let last = open.last, last.end <= start {
                open.removeLast()
            }
            if let token = node.as(TokenSyntax.self) {
                guard let owner = open.last?.index, token.presence == .present else { continue }
                lines.lineRange(of: token).forEach { line in
                    if owners[line].last != owner {
                        owners[line].append(owner)
                    }
                }
            } else if isUnit(node, topLevel: topLevel) {
                units.append(Unit(
                    lineRange: commentedLineRange(of: node, in: lines),
                    body: body(of: node, in: lines),
                    parent: open.last?.index
                ))
                open.append((units.count - 1, node.endPositionBeforeTrailingTrivia.utf8Offset))
            }
        }
        return (units, owners)
    }

    /// The lines of `node`, from the comments directly above it, its doc
    /// comment among them, to its last token: a pull request that edits
    /// only a doc comment changes what it documents.
    private static func commentedLineRange(of node: Syntax, in lines: SourceLines) -> ClosedRange<Int> {
        let tokens = lines.lineRange(of: node)
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
