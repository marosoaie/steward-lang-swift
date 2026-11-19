import Foundation

/// A Markdown document whose examples are compiled, as the tests read it:
/// its fenced blocks, each named by the `<!-- Marker: name -->` line before
/// it, and the examples, named by the `// Marker: name` and
/// `// Marker: end` lines around them, where the marker is the document's
/// own: `README` for README.md, `Recipe` for docs/recipes.md.
struct Document {
    /// Which document, its marker, and where its examples are.
    struct Source {
        var path: String
        var marker: String
        var exampleDirectories: [String]
    }

    static let readme = Source(
        path: "README.md",
        marker: "README",
        exampleDirectories: ["Tests/ReadmeDangerfile", "Tests/StewardSwiftTests/Readme"]
    )
    /// The recipes are this repository's own Dangerfile's rules, which its
    /// own package compiles and tests.
    static let recipes = Source(
        path: "docs/recipes.md",
        marker: "Recipe",
        exampleDirectories: ["Dangerfile/Sources/Dangerfile"]
    )

    /// A fenced block.
    struct Block {
        /// The fence's info string, such as `swift`.
        var language: String
        /// The name its marker gives, if it has one.
        var name: String?
        /// Its lines, joined with line feeds.
        var text: String
        /// The line of its opening fence.
        var line: Int
    }

    /// The repository's root, found from this file's path.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    let source: Source
    let text: String
    let blocks: [Block]

    init(_ source: Source) throws {
        self.source = source
        text = try String(contentsOf: Self.root.appendingPathComponent(source.path), encoding: .utf8)
        blocks = Self.blocks(
            in: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
            marker: source.marker
        )
    }

    /// The block named `name`.
    func block(_ name: String) throws -> Block {
        guard let block = blocks.first(where: { $0.name == name }) else {
            throw SubprocessError("\(source.path) has no block named \(name)")
        }
        return block
    }

    /// The lines between `<!-- Marker: name -->` and the next
    /// `<!-- Marker: end -->`.
    func section(_ name: String) throws -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(of: "<!-- \(source.marker): \(name) -->"),
              let end = lines[start...].firstIndex(of: "<!-- \(source.marker): end -->")
        else { throw SubprocessError("\(source.path) has no section named \(name)") }
        return Array(lines[(start + 1)..<end])
    }

    /// The examples, by name, each without the indentation its lines
    /// share.
    func examples() throws -> [String: String] {
        let files = source.exampleDirectories.flatMap { directory in
            let root = Self.root
            let url = root.appendingPathComponent(directory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            // Hidden files aren't sources, as SwiftPM has it.
            return names.filter { $0.hasSuffix(".swift") && !$0.hasPrefix(".") }.sorted()
                .map { url.appendingPathComponent($0) }
        }
        let found = try files.flatMap { file in
            Self.regions(in: try String(contentsOf: file, encoding: .utf8), marker: source.marker)
        }
        let repeated = Dictionary(grouping: found) { $0.0 }.filter { $0.value.count > 1 }.keys.sorted()
        guard repeated.isEmpty else {
            throw SubprocessError("\(source.path)'s examples have more than one named \(repeated)")
        }
        return Dictionary(uniqueKeysWithValues: found)
    }

    private static func blocks(in lines: [String], marker: String) -> [Block] {
        // An imperative loop: whether a fence is open is the state carried
        // from one line to the next.
        var blocks: [Block] = []
        var open: Block?
        var body: [String] = []
        for (index, line) in lines.enumerated() {
            if var current = open {
                if line == "```" {
                    current.text = body.joined(separator: "\n")
                    blocks.append(current)
                    open = nil
                    body = []
                } else {
                    body.append(line)
                }
            } else if line.hasPrefix("```") {
                let previous = lines[..<index].last { !$0.isEmpty }
                open = Block(
                    language: String(line.dropFirst(3)),
                    name: previous.flatMap { name(inMarker: $0, marker: marker) },
                    text: "",
                    line: index + 1
                )
            }
        }
        return blocks
    }

    /// `name` in `<!-- Marker: name -->`.
    private static func name(inMarker line: String, marker: String) -> String? {
        let prefix = "<!-- \(marker): "
        guard line.hasPrefix(prefix), line.hasSuffix(" -->") else { return nil }
        return String(line.dropFirst(prefix.count).dropLast(" -->".count))
    }

    /// The regions of `source` between `// Marker: name` and
    /// `// Marker: end`, dedented.
    private static func regions(in source: String, marker word: String) -> [(String, String)] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let marker = "// \(word): "
        return lines.indices.compactMap { index -> (String, String)? in
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(marker), trimmed != "\(marker)end" else { return nil }
            let body = lines[(index + 1)...].prefix { $0.trimmingCharacters(in: .whitespaces) != "\(marker)end" }
            let indent = body.filter { !$0.isEmpty }.map { $0.prefix { $0 == " " }.count }.min() ?? 0
            let text = body.map { $0.isEmpty ? $0 : String($0.dropFirst(indent)) }.joined(separator: "\n")
            return (String(trimmed.dropFirst(marker.count)), text)
        }
    }
}
