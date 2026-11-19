import StewardSwift
import Testing

/// Inline sources, read as a pull request's file at `path` would be.
enum Sample {
    static let path = "Sources/App/Sample.swift"

    static func file(_ source: String) async throws -> SwiftFile {
        try await SwiftFile(source: source, path: path)
    }

    static func functions(in source: String) async throws -> [FunctionDeclaration] {
        try await file(source).functions
    }

    /// The only function in `source`.
    /// (SwiftSyntax, which StewardSwift re-exports, has a `SourceLocation`
    /// of its own.)
    static func function(
        _ source: String,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) async throws -> FunctionDeclaration {
        let functions = try await functions(in: source)
        try #require(
            functions.count == 1,
            "expected one function, found \(functions.map(\.name))",
            sourceLocation: sourceLocation
        )
        return functions[0]
    }

    /// The function named `name` in `source`.
    static func function(
        named name: String,
        in source: String,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) async throws -> FunctionDeclaration {
        try #require(try await functions(in: source).first { $0.name == name }, sourceLocation: sourceLocation)
    }
}
