import Foundation
import StewardSwift

/// The compiler's view of swift-argument-parser's functions: its symbol
/// graph, at the minimum access level `private`, which
/// `swift package dump-symbol-graph` writes after building the package.
///
/// Building takes a minute, so the tests that read it run only when
/// `STEWARD_SWIFT_ORACLE=1` is set (CI's macos-tests job sets it).
enum SymbolGraphOracle {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["STEWARD_SWIFT_ORACLE"] == "1" && Corpus.isNetworkAllowed
    }

    /// A function the symbol graph lists at a place in the source.
    struct Function: Sendable, CustomStringConvertible {
        var path: String
        var line: Int
        var name: String
        var access: AccessLevel.Level?
        var isAsync: Bool
        var isThrowing: Bool
        var isStatic: Bool

        var description: String {
            "\(path):\(line) \(name)"
        }
    }

    /// The checkout the graph was built from, and the functions it lists.
    struct Graph: Sendable {
        var root: URL
        var functions: [Function]
    }

    /// The functions the symbol graph lists with a location in the source.
    /// Synthesized and inherited members, which no line declares, are left
    /// out.
    static let graph = Task<Graph, any Error> {
        let checkout = try await Corpus.argumentParser.value
        // A copy, so the build's products stay out of the cache.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("steward-lang-swift-oracle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: checkout, to: root)
        let output = try run([
            "swift", "package", "--package-path", root.path,
            "dump-symbol-graph", "--minimum-access-level", "private",
        ])
        let prefix = "Files written to "
        guard let line = output.split(separator: "\n").last(where: { $0.hasPrefix(prefix) }) else {
            throw CorpusError("dump-symbol-graph didn't say where it wrote: \(output.suffix(500))")
        }
        let directory = URL(fileURLWithPath: String(line.dropFirst(prefix.count)))
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let functions = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".symbols.json") }
            .flatMap { name in
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let file = try JSONDecoder().decode(GraphFile.self, from: data)
                return file.symbols.compactMap { $0.function(under: rootPath) }
            }
        return Graph(root: root, functions: functions)
    }

    private static func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let command = arguments.joined(separator: " ")
            throw CorpusError("\(command) exited with \(process.terminationStatus): \(text.suffix(2000))")
        }
        return text
    }
}

private struct GraphFile: Decodable {
    var symbols: [GraphSymbol]
}

private struct GraphKind: Decodable {
    var identifier: String
}

private struct GraphNames: Decodable {
    var title: String
}

private struct GraphPosition: Decodable {
    var line: Int
}

private struct GraphLocation: Decodable {
    var uri: String
    var position: GraphPosition
}

private struct GraphFragment: Decodable {
    var kind: String
    var spelling: String
}

private struct GraphSymbol: Decodable {
    var kind: GraphKind
    var names: GraphNames
    var accessLevel: String
    var location: GraphLocation?
    var declarationFragments: [GraphFragment]?

    static let functionKinds: Set = ["swift.func", "swift.method", "swift.type.method", "swift.func.op"]

    func function(under root: String) -> SymbolGraphOracle.Function? {
        guard Self.functionKinds.contains(kind.identifier),
              let location,
              let url = URL(string: location.uri)
        else { return nil }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(root + "/") else { return nil }
        let keywords = ownKeywords
        return SymbolGraphOracle.Function(
            path: String(path.dropFirst(root.count + 1)),
            // The graph counts lines from 0.
            line: location.position.line + 1,
            name: String(names.title.prefix { $0 != "(" }),
            access: AccessLevel.Level.allCases.first { $0.description == accessLevel },
            isAsync: keywords.contains("async"),
            isThrowing: keywords.contains("throws") || keywords.contains("rethrows"),
            isStatic: kind.identifier == "swift.type.method"
                || keywords.contains("static") || keywords.contains("class")
        )
    }

    /// The keywords that are the function's own: its modifiers, and the
    /// effects after its parameters and before `->`, but not those of a
    /// closure type among its parameters or in its return type.
    var ownKeywords: Set<String> {
        // An imperative loop: the depth of parentheses and whether the
        // parameters or the arrow have been passed are the state.
        var keywords: Set<String> = []
        var depth = 0
        var parametersDone = false
        var arrowSeen = false
        for fragment in declarationFragments ?? [] {
            if fragment.kind == "keyword" {
                let isModifier = !parametersDone && depth == 0
                let isEffect = parametersDone && depth == 0 && !arrowSeen
                if isModifier || isEffect {
                    keywords.insert(fragment.spelling)
                }
                continue
            }
            fragment.spelling.forEach { character in
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 { parametersDone = true }
                }
            }
            if parametersDone && depth == 0 && fragment.spelling.contains("->") {
                arrowSeen = true
            }
        }
        return keywords
    }
}
