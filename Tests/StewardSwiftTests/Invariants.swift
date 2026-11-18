import StewardSwift
import StewardTesting
import Testing

/// What holds for a file read from any source, valid Swift or not.
enum Invariants {
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
