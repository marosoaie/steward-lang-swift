import Foundation
import StewardSwift
import Testing

/// The compiler's view of swift-argument-parser's functions, types and
/// members, and their doc comments: its symbol graph, at the minimum access level `private`, which the compiler writes
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
        /// The name with its argument labels, such as `parse(_:into:)`.
        var title: String
        var access: AccessLevel.Level?
        var isAsync: Bool
        var isThrowing: Bool
        var isStatic: Bool

        var description: String {
            "\(path):\(line) \(name)"
        }
    }

    /// A symbol the graph lists at a place in the source, with its doc
    /// comment.
    struct Documented: Sendable, CustomStringConvertible {
        var path: String
        var line: Int
        /// The name without parameters, such as `init` or `parse`.
        var name: String
        var kind: String
        /// The doc comment's lines as the graph lists them, joined, with
        /// whitespace-only lines at the start and the end dropped, or nil
        /// when the graph has none.
        var documentation: String?

        var description: String {
            "\(path):\(line) \(kind) \(name)"
        }
    }

    /// The checkout whose sources the graph describes, the functions it
    /// lists, and every symbol it lists with its doc comment.
    struct Graph: Sendable {
        var root: URL
        var functions: [Function]
        var documented: [Documented]
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
        let symbols = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".symbols.json") }
            .flatMap { name in
                let data = try Data(contentsOf: directory.appendingPathComponent(name))
                return try JSONDecoder().decode(GraphFile.self, from: data).symbols
            }
        let functions = symbols.compactMap { $0.function(under: rootPath) }
            .sorted { ($0.path, $0.line, $0.title) < ($1.path, $1.line, $1.title) }
        // The initializers the compiler makes, implicit and memberwise, have
        // no declaration: the graph lists them at their type's name.
        let typeKinds: Set = ["swift.struct", "swift.class", "swift.enum", "swift.actor", "swift.protocol"]
        let typePositions = Set(symbols.filter { typeKinds.contains($0.kind.identifier) }.compactMap(\.place))
        let documented = symbols
            .filter { !($0.kind.identifier == "swift.init" && $0.place.map(typePositions.contains) == true) }
            .compactMap { $0.documented(under: rootPath) }
        // The copy's sources are the checkout's.
        return Graph(root: checkout, functions: functions, documented: documented)
    }

    /// The doc comment the compiler reads for each symbol in `source`, by
    /// name, from the symbol graph of a package of that one file, which
    /// `swift build` builds, as it builds the corpus.
    static func documentation(ofSymbolsIn source: String) throws -> [String: String?] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("steward-lang-swift-doc-oracle-\(UUID().uuidString)", isDirectory: true)
        let sources = root.appendingPathComponent("Sources/Shapes", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Shapes", targets: [.target(name: "Shapes")])
            """
        try Data(manifest.utf8).write(to: root.appendingPathComponent("Package.swift"))
        try Data(source.utf8).write(to: sources.appendingPathComponent("Shapes.swift"))
        let directory = root.appendingPathComponent(".symbol-graphs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let compilerFlags = ["-emit-symbol-graph", "-emit-symbol-graph-dir", directory.path]
        _ = try run(["swift", "build", "--package-path", root.path] + compilerFlags.flatMap { ["-Xswiftc", $0] })
        let data = try Data(contentsOf: directory.appendingPathComponent("Shapes.symbols.json"))
        let symbols = try JSONDecoder().decode(GraphFile.self, from: data).symbols
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        return Dictionary(
            symbols.compactMap { $0.documented(under: rootPath) }.map { ($0.name, $0.documentation) },
            uniquingKeysWith: { first, _ in first }
        )
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

private struct GraphPosition: Decodable, Hashable {
    var line: Int
    var character: Int?
}

private struct GraphLocation: Decodable {
    var uri: String
    var position: GraphPosition
}

private struct GraphFragment: Decodable {
    var kind: String
    var spelling: String
}

private struct GraphDocLine: Decodable {
    var text: String
}

private struct GraphDocComment: Decodable {
    var lines: [GraphDocLine]

    /// The lines, joined, without whitespace-only lines at the start and
    /// the end, which the model drops.
    var text: String {
        let isBlank = { (line: GraphDocLine) in line.text.allSatisfy { $0 == " " || $0 == "\t" } }
        let lastText = lines.lastIndex { !isBlank($0) } ?? -1
        return lines.prefix(lastText + 1).drop(while: isBlank).map(\.text).joined(separator: "\n")
    }
}

private struct GraphSymbol: Decodable {
    var kind: GraphKind
    var identifier: GraphIdentifier
    var names: GraphNames
    var pathComponents: [String]?
    var accessLevel: String
    var location: GraphLocation?
    var declarationFragments: [GraphFragment]?
    var docComment: GraphDocComment?

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
            title: names.title,
            access: AccessLevel.Level.allCases.first { $0.description == accessLevel },
            isAsync: keywords.contains("async"),
            isThrowing: keywords.contains("throws") || keywords.contains("rethrows"),
            isStatic: kind.identifier == "swift.type.method"
                || keywords.contains("static") || keywords.contains("class")
        )
    }

    /// Where the symbol is: its file and position.
    var place: String? {
        location.map { "\($0.uri):\($0.position.line):\($0.position.character ?? -1)" }
    }

    /// The symbol with its doc comment, if it's in a file under `root`
    /// and the model reads it: top-level variables aren't members, so they
    /// are left out, as are synthesized copies.
    func documented(under root: String) -> SymbolGraphOracle.Documented? {
        guard kind.identifier != "swift.var",
              !identifier.precise.contains("::SYNTHESIZED::"),
              let location,
              let url = URL(string: location.uri)
        else { return nil }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(root + "/") else { return nil }
        return SymbolGraphOracle.Documented(
            path: String(path.dropFirst(root.count + 1)),
            line: location.position.line + 1,
            name: String((pathComponents?.last ?? names.title).prefix { $0 != "(" }),
            kind: kind.identifier,
            documentation: docComment?.text
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
