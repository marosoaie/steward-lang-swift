import Foundation
import StewardSwift
import Testing

/// The compiler's view of swift-argument-parser's functions: its symbol
/// graph, at the minimum access level `private`, which the compiler writes
/// while it builds the package. (`swift package dump-symbol-graph` would
/// do too, but before Swift 6.4 it also extracts the package's test
/// module, which fails, so the command exits with an error.)
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

    /// The checkout whose sources the graph describes, and the functions it
    /// lists.
    struct Graph: Sendable {
        var root: URL
        var functions: [Function]
    }

    /// The functions the symbol graph lists with a location in the source,
    /// each once. Members without a location, and the copies the graph
    /// makes of a protocol extension's default for each conforming type
    /// (`::SYNTHESIZED::`, at the original's location), are left out.
    static let graph = Task<Graph, any Error> {
        let checkout = try await Corpus.argumentParser.value
        // Built in a copy, so the build's products stay out of the cache,
        // and removed once its graph is read.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("steward-lang-swift-oracle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: checkout, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent(".symbol-graphs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let compilerFlags = [
            "-emit-symbol-graph", "-emit-symbol-graph-dir", directory.path,
            "-symbol-graph-minimum-access-level", "private",
        ]
        _ = try run(["swift", "build", "--package-path", root.path] + compilerFlags.flatMap { ["-Xswiftc", $0] })
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let listed = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".symbols.json") }
            .flatMap { name in
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                let file = try JSONDecoder().decode(GraphFile.self, from: data)
                return file.symbols.compactMap { $0.function(under: rootPath) }
            }
        // A module's graph and its extensions' graphs can list one function
        // twice; keep the first of each.
        let functions = Dictionary(grouping: listed) { "\($0.path):\($0.line):\($0.name)" }
            .values.compactMap(\.first)
            .sorted { ($0.path, $0.line, $0.name) < ($1.path, $1.line, $1.name) }
        // The copy's sources are the checkout's.
        return Graph(root: checkout, functions: functions)
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

private struct GraphIdentifier: Decodable {
    var precise: String
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
    var identifier: GraphIdentifier
    var names: GraphNames
    var accessLevel: String
    var location: GraphLocation?
    var declarationFragments: [GraphFragment]?

    static let functionKinds: Set = ["swift.func", "swift.method", "swift.type.method", "swift.func.op"]

    func function(under root: String) -> SymbolGraphOracle.Function? {
        guard Self.functionKinds.contains(kind.identifier),
              !identifier.precise.contains("::SYNTHESIZED::"),
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
            // Character by character: the printer joins text such as
            // `() -> (` into one fragment, with the arrow between brackets.
            var previous: Character?
            fragment.spelling.forEach { character in
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 { parametersDone = true }
                } else if character == ">", previous == "-", parametersDone, depth == 0 {
                    arrowSeen = true
                }
                previous = character
            }
        }
        return keywords
    }
}

/// The oracle's own reading of a symbol, which needs no build.
@Suite("Symbol graph oracle's reading")
struct SymbolGraphReadingTests {
    fileprivate static func symbol(_ fragments: [(String, String)], kind: String = "swift.func") throws -> GraphSymbol {
        let json = """
            {"kind": {"identifier": "\(kind)"}, "identifier": {"precise": "s:1f"}, "names": {"title": "f()"},
             "accessLevel": "public", "location": {"uri": "file:///root/F.swift", "position": {"line": 0}},
             "declarationFragments": [\(fragments.map { #"{"kind": "\#($0.0)", "spelling": "\#($0.1)"}"# }
                .joined(separator: ", "))]}
            """
        return try JSONDecoder().decode(GraphSymbol.self, from: Data(json.utf8))
    }

    @Test("an effect in a closure type, among the parameters or in the return type, isn't the function's")
    func closureEffects() throws {
        // `func handler() -> (Int) throws -> Void`, as the printer splits it.
        let returning = try Self.symbol([
            ("keyword", "func"), ("text", " "), ("identifier", "handler"), ("text", "() -> ("),
            ("typeIdentifier", "Int"), ("text", ") "), ("keyword", "throws"), ("text", " -> "),
            ("typeIdentifier", "Void"),
        ])
        #expect(!returning.ownKeywords.contains("throws"))
        // `func f(_ g: () async -> Void) async throws`
        let taking = try Self.symbol([
            ("keyword", "func"), ("text", " "), ("identifier", "f"), ("text", "(_ g: () "),
            ("keyword", "async"), ("text", " -> "), ("typeIdentifier", "Void"), ("text", ") "),
            ("keyword", "async"), ("text", " "), ("keyword", "throws"),
        ])
        #expect(taking.ownKeywords == ["func", "async", "throws"])
    }

    @Test("a synthesized copy of a protocol extension's default isn't read")
    func synthesized() throws {
        let json = """
            {"kind": {"identifier": "swift.method"}, "identifier": {"precise": "s:1P1fyyF::SYNTHESIZED::s:1S"},
             "names": {"title": "f()"}, "accessLevel": "public",
             "location": {"uri": "file:///root/F.swift", "position": {"line": 0}}}
            """
        let symbol = try JSONDecoder().decode(GraphSymbol.self, from: Data(json.utf8))
        #expect(symbol.function(under: "/root") == nil)
    }
}
