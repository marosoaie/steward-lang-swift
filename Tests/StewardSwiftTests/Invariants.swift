import StewardSwift
import StewardTesting
import Testing

/// What holds for a file read from any source, valid Swift or not.
enum Invariants {
    /// A declaration's location and lines, with what to call it.
    struct Span {
        var what: String
        var location: Location
        var lineRange: ClosedRange<Int>

        /// The types, member blocks and members of `file`.
        static func all(in file: SwiftFile) -> [Span] {
            file.types.map { Span(what: "type \($0.name)", location: $0.location, lineRange: $0.lineRange) }
                + file.memberBlocks.map {
                    Span(what: "block of \($0.owner)", location: $0.location, lineRange: $0.lineRange)
                }
                + file.memberBlocks.flatMap { block in
                    block.members.map {
                        Span(what: "member \($0.name)", location: $0.location, lineRange: $0.lineRange)
                    }
                }
        }
    }

    static func check(_ file: SwiftFile, source: String, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let lineCount = source.utf8.reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        let valid = 1...lineCount
        file.functions.forEach { function in
            let lineRange = function.lineRange
            #expect(
                valid.contains(lineRange.lowerBound) && valid.contains(lineRange.upperBound),
                "\(function.name)'s lines \(lineRange) are outside 1...\(lineCount)",
                sourceLocation: sourceLocation
            )
            #expect(function.location.path == file.path, sourceLocation: sourceLocation)
            #expect(
                lineRange.contains(function.location.line ?? 0),
                "\(function.name) at \(function.location) is outside its lines \(lineRange)",
                sourceLocation: sourceLocation
            )
            let parts = function.parameters.map(\.location) + function.attributes.map(\.location)
            #expect(
                parts.allSatisfy { lineRange.contains($0.line ?? 0) && $0.path == file.path },
                "\(function.name)'s parameters or attributes are outside its lines \(lineRange)",
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
        Span.all(in: file).forEach { span in
            let (what, location, lineRange) = (span.what, span.location, span.lineRange)
            #expect(
                valid.contains(lineRange.lowerBound) && valid.contains(lineRange.upperBound)
                    && lineRange.contains(location.line ?? 0) && location.path == file.path,
                "\(what) at \(location) is outside its lines \(lineRange) or the file's 1...\(lineCount)",
                sourceLocation: sourceLocation
            )
        }
        file.memberBlocks.forEach { block in
            let functionMembers = block.members.filter { $0.kind == .function }
            #expect(
                block.members.allSatisfy { member in
                    block.lineRange.contains(member.lineRange.lowerBound)
                        && block.lineRange.contains(member.lineRange.upperBound)
                        && sequence(first: Syntax(member.syntax), next: \.parent).contains { $0.id == block.syntax.id }
                },
                "a member of \(block.owner) is outside its block's lines \(block.lineRange) or its node",
                sourceLocation: sourceLocation
            )
            #expect(
                block.members.allSatisfy { member in
                    member.attributes.allSatisfy {
                        member.lineRange.contains($0.location.line ?? 0) && $0.location.path == file.path
                    }
                },
                "an attribute of a member of \(block.owner) is outside the member's lines",
                sourceLocation: sourceLocation
            )
            #expect(
                block.functions.map(\.name) == functionMembers.map(\.name)
                    && block.functions.map(\.attributes) == functionMembers.map(\.attributes)
                    && block.functions.map(\.documentation) == functionMembers.map(\.documentation)
                    && block.functions.map(\.modifiers) == functionMembers.map(\.modifiers),
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
