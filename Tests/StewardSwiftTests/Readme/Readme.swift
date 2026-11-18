import Foundation

/// README.md as the tests read it: its fenced blocks, each named by the
/// `<!-- README: name -->` line before it, and the examples the tests
/// compile, named by the `// README: name` and `// README: end` lines
/// around them.
struct Readme {
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

    /// Where the compiled examples are.
    static let exampleDirectories = ["Tests/ReadmeDangerfile", "Tests/StewardSwiftTests/Readme"]

    let text: String
    let blocks: [Block]

    init() throws {
        text = try String(contentsOf: Self.root.appendingPathComponent("README.md"), encoding: .utf8)
        blocks = Self.blocks(in: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    }

    /// The block named `name`.
    func block(_ name: String) throws -> Block {
        guard let block = blocks.first(where: { $0.name == name }) else {
            throw SubprocessError("README.md has no block named \(name)")
        }
        return block
    }

    /// The lines between `<!-- README: name -->` and the next
    /// `<!-- README: end -->`.
    func section(_ name: String) throws -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(of: "<!-- README: \(name) -->"),
              let end = lines[start...].firstIndex(of: "<!-- README: end -->")
        else { throw SubprocessError("README.md has no section named \(name)") }
        return Array(lines[(start + 1)..<end])
    }

    /// The compiled examples, by name, each without the indentation its
    /// lines share.
    static func examples() throws -> [String: String] {
        let files = exampleDirectories.flatMap { directory in
            let url = root.appendingPathComponent(directory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.filter { $0.hasSuffix(".swift") }.sorted().map { url.appendingPathComponent($0) }
        }
        let found = try files.flatMap { file in
            Self.regions(in: try String(contentsOf: file, encoding: .utf8))
        }
        return Dictionary(found) { first, _ in first }
    }

    private static func blocks(in lines: [String]) -> [Block] {
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
                let marker = lines[..<index].last { !$0.isEmpty }
                open = Block(
                    language: String(line.dropFirst(3)),
                    name: marker.flatMap(name(inMarker:)),
                    text: "",
                    line: index + 1
                )
            }
        }
        return blocks
    }

    /// `name` in `<!-- README: name -->`.
    private static func name(inMarker line: String) -> String? {
        guard line.hasPrefix("<!-- README: "), line.hasSuffix(" -->") else { return nil }
        return String(line.dropFirst("<!-- README: ".count).dropLast(" -->".count))
    }

    /// The regions of `source` between `// README: name` and
    /// `// README: end`, dedented.
    private static func regions(in source: String) -> [(String, String)] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let marker = "// README: "
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
