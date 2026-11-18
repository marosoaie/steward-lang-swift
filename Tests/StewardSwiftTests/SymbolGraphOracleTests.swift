import Foundation
import StewardSwift
import StewardTesting
import Testing

/// The model against the compiler: every function swift-argument-parser's
/// symbol graph lists, at minimum access level `private`, is read at the
/// same line with the same name, `async`, `throws`, access level and
/// `static`.
@Suite("Symbol graph oracle", .enabled(if: SymbolGraphOracle.isEnabled), .timeLimit(.minutes(20)))
struct SymbolGraphOracleTests {
    @Test("every function in the compiler's symbol graph is read alike")
    func functionsMatchTheSymbolGraph() async throws {
        let graph = try await SymbolGraphOracle.graph.value
        #expect(graph.functions.count > 300, "the graph listed only \(graph.functions.count) functions with a location")
        let byFile = Dictionary(grouping: graph.functions, by: \.path)
        let differences = try byFile.keys.sorted().flatMap { path -> [String] in
            let data = try Data(contentsOf: graph.root.appendingPathComponent(path))
            let file = try SwiftFile(source: String(decoding: data, as: UTF8.self), path: path)
            return (byFile[path] ?? []).compactMap { expected in Self.difference(expected, in: file) }
        }
        #expect(
            differences.isEmpty,
            "\(differences.count) differences:\n\(differences.prefix(40).joined(separator: "\n"))"
        )
    }

    /// What the model reads differently from the graph for `expected`, or
    /// nil when it reads the same.
    static func difference(_ expected: SymbolGraphOracle.Function, in file: SwiftFile) -> String? {
        let atLine = file.functions.filter { $0.location.line == expected.line }
        guard let function = atLine.first(where: { $0.name == expected.name }) else {
            return "\(expected): not read (at that line: \(atLine.map(\.name)))"
        }
        let differing = [
            ("access", "\(function.access.level)", expected.access.map(String.init(describing:)) ?? "?"),
            ("async", "\(function.isAsync)", "\(expected.isAsync)"),
            ("throws", "\(function.isThrowing)", "\(expected.isThrowing)"),
            ("static", "\(function.isStatic)", "\(expected.isStatic)"),
        ]
        .filter { $0.1 != $0.2 }
        .map { "\($0.0): read \($0.1), compiler \($0.2)" }
        return differing.isEmpty ? nil : "\(expected): \(differing.joined(separator: ", "))"
    }
}
