import StewardSwift
import StewardTesting
import Testing

/// What holds for a file read from any source, valid Swift or not.
enum Invariants {
    /// A declaration's location and lines, with what to call it.
    struct Span {
        var what: String
        var location: Location
        var lines: ClosedRange<Int>
    }

    static func check(_ file: SwiftFile, source: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let lineCount = source.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        let valid = 1...lineCount
        file.functions.forEach { function in
            let lines = function.lines
            #expect(valid.contains(lines.lowerBound) && valid.contains(lines.upperBound),
                    "\(function.name)'s lines \(lines) are outside 1...\(lineCount)", sourceLocation: sourceLocation)
            #expect(function.location.path == file.path, sourceLocation: sourceLocation)
            #expect(
                lines.contains(function.location.line ?? 0),
                "\(function.name) at \(function.location) is outside its lines \(lines)",
                sourceLocation: sourceLocation
            )
            let parts = function.parameters.map(\.location) + function.attributes.map(\.location)
            #expect(
                parts.allSatisfy { lines.contains($0.line ?? 0) && $0.path == file.path },
                "\(function.name)'s parameters or attributes are outside its lines \(lines)",
                sourceLocation: sourceLocation
            )
        }
    }

    /// What holds for the types, member blocks, members and imports of a
    /// file read from any source.
    static func checkDeclarations(
        _ file: SwiftFile,
        source: String,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) {
        let lineCount = source.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        let valid = 1...lineCount
        let spans: [Span] =
            file.types.map { Span(what: "type \($0.name)", location: $0.location, lines: $0.lines) }
            + file.memberBlocks.map { Span(what: "block of \($0.owner)", location: $0.location, lines: $0.lines) }
            + file.memberBlocks.flatMap { block in
                block.members.map { Span(what: "member \($0.name)", location: $0.location, lines: $0.lines) }
            }
        spans.forEach { span in
            let (what, location, lines) = (span.what, span.location, span.lines)
            #expect(
                valid.contains(lines.lowerBound) && valid.contains(lines.upperBound)
                    && lines.contains(location.line ?? 0) && location.path == file.path,
                "\(what) at \(location) is outside its lines \(lines) or the file's 1...\(lineCount)",
                sourceLocation: sourceLocation
            )
        }
        file.memberBlocks.forEach { block in
            #expect(
                block.members.allSatisfy {
                    block.lines.contains($0.lines.lowerBound) && block.lines.contains($0.lines.upperBound)
                },
                "a member of \(block.owner) is outside its block's lines \(block.lines)",
                sourceLocation: sourceLocation
            )
            #expect(
                block.members.allSatisfy { member in
                    member.attributes.allSatisfy {
                        member.lines.contains($0.location.line ?? 0) && $0.location.path == file.path
                    }
                },
                "an attribute of a member of \(block.owner) is outside the member's lines",
                sourceLocation: sourceLocation
            )
            #expect(
                block.functions.map(\.name) == block.members.filter { $0.kind == .function }.map(\.name),
                "\(block.owner)'s functions and function members disagree",
                sourceLocation: sourceLocation
            )
        }
        #expect(
            file.imports.allSatisfy { valid.contains($0.location.line ?? 0) && $0.location.path == file.path },
            sourceLocation: sourceLocation
        )
    }

    /// The `func` keywords that the source writes and that start a function
    /// declaration, found by swift-syntax's own token iteration rather than
    /// the package's walk.
    static func writtenFunctionKeywords(in file: SwiftFile) -> Int {
        file.syntax.tokens(viewMode: .sourceAccurate)
            .filter { $0.tokenKind == .keyword(.func) && $0.parent?.is(FunctionDeclSyntax.self) == true }
            .count
    }

    /// The functions the package found whose `func` keyword is written.
    static func functionsWithWrittenKeyword(in file: SwiftFile) -> Int {
        file.functions.filter { $0.syntax.funcKeyword.presence == .present }.count
    }
}
