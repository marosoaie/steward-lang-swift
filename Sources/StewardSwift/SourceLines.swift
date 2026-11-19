import SwiftSyntax

/// Line numbers for positions in a source, counted as git counts them, so
/// that they match the lines of a pull request's diff: a line ends at
/// `\n`, and a `\r` on its own doesn't end one. (swift-syntax's
/// `SourceLocationConverter` counts a lone `\r` as a line break, and walks
/// the tree recursively to build its table.)
struct SourceLines: Sendable {
    /// The UTF-8 offset at which each line starts, in order; the first is 0.
    private let starts: [Int]

    init(source: String) {
        starts = [0] + source.utf8.enumerated().lazy
            .filter { $0.element == UInt8(ascii: "\n") }
            .map { $0.offset + 1 }
    }

    /// How many lines the source has: one more than its line feeds, so a
    /// source that ends with one has an empty last line.
    var count: Int {
        starts.count
    }

    /// The 1-based line that holds the byte at `offset`; an offset past the
    /// end is on the last line.
    func line(atUTF8Offset offset: Int) -> Int {
        // A binary search for the last start at or before `offset`.
        var low = 0
        var high = starts.count
        while high - low > 1 {
            let middle = low + (high - low) / 2
            if starts[middle] <= offset {
                low = middle
            } else {
                high = middle
            }
        }
        return low + 1
    }

    /// The 1-based column of the byte at `offset`, in bytes from the start
    /// of its line.
    func column(atUTF8Offset offset: Int) -> Int {
        offset - starts[line(atUTF8Offset: offset) - 1] + 1
    }

    /// The lines `node` covers, from its first token to its last, without
    /// the trivia around them.
    func lines(of node: some SyntaxProtocol) -> ClosedRange<Int> {
        let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = node.endPositionBeforeTrailingTrivia.utf8Offset
        let first = line(atUTF8Offset: start)
        let last = line(atUTF8Offset: Swift.max(start, end - 1))
        return first...Swift.max(first, last)
    }

    /// The line on which `node`'s first token starts.
    func line(of node: some SyntaxProtocol) -> Int {
        line(atUTF8Offset: node.positionAfterSkippingLeadingTrivia.utf8Offset)
    }
}
