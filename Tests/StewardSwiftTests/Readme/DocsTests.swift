import Foundation
import StewardSwift
import Testing

/// docs/ against the code: the recipes are the repository's own
/// Dangerfile's rules, word for word, and the model reference names every
/// public property of every model type.
@Suite("The docs")
struct DocsTests {
    @Test("every Swift block in docs/recipes.md is one of the repository's own rules, and every rule is in it")
    func recipes() throws {
        let recipes = try Document(Document.recipes)
        try ReadmeTests.expectExamples(in: recipes, except: [])
        try ReadmeTests.expectFences(in: recipes)
    }

    @Test("docs/model.md has a section for each public model type, whose rows are its public properties, no more")
    func model() async throws {
        let reference = try String(
            contentsOf: Document.root.appendingPathComponent("docs/model.md"),
            encoding: .utf8
        )
        let sections = Dictionary(
            reference.components(separatedBy: "\n## ").dropFirst().map { section in
                (String(section.prefix { $0 != "\n" }), section)
            }
        ) { first, _ in first }
        let sources = Document.root.appendingPathComponent("Sources/StewardSwift")
        let names = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }
        // Read with the model itself: the public types at the top of each
        // file, and the public properties and cases of their braces and of
        // the extensions of them.
        let files = try await names.asyncMap { name in
            try await SwiftFile(
                source: String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8), path: name
            )
        }
        let types = files.flatMap(\.types).filter { type in
            type.access.level >= .public && type.syntax.parent?.parent?.parent?.is(SourceFileSyntax.self) == true
        }
        let extensions = files.flatMap(\.memberBlocks).filter { if case .extension = $0.owner { true } else { false } }
        #expect(types.count >= 12)
        types.forEach { type in
            guard let section = sections["`\(type.name)`"] else {
                Issue.record("docs/model.md has no section for \(type.name)")
                return
            }
            let members = type.members + extensions.filter { $0.owner == .extension(TypeName(type.name)) }
                .flatMap(\.members)
            let names = Set(members.filter { [.property, .case].contains($0.kind) && $0.access.level >= .public }
                .map(\.name)).subtracting(["description"])
            // Each table row's first cell names one of them, and each of
            // them has a row.
            let rows = Set(section.split(separator: "\n").compactMap { line in
                line.firstMatch(of: /^\| `(\w+)` \|/).map { String($0.1) }
            })
            #expect(rows == names, "docs/model.md's \(type.name): rows \(rows.sorted()), members \(names.sorted())")
        }
    }
}
