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
        try ReadmeTests.expectExamples(in: Document(Document.recipes), except: [])
    }

    @Test("docs/model.md has a section for each public model type, naming each of its public properties")
    func model() throws {
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
        // file, and the public properties and cases their braces declare.
        let types = try names.flatMap { name in
            let source = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let file = try SwiftFile(source: source, path: name)
            return file.types.filter { type in
                type.access.level >= .public && type.syntax.parent?.parent?.parent?.is(SourceFileSyntax.self) == true
            }
        }
        #expect(types.count >= 12)
        types.forEach { type in
            guard let section = sections["`\(type.name)`"] else {
                Issue.record("docs/model.md has no section for \(type.name)")
                return
            }
            type.members
                .filter { [.property, .case].contains($0.kind) && $0.access.level >= .public }
                .filter { $0.name != "description" }
                .forEach { member in
                    #expect(
                        section.contains("`\(member.name)`"),
                        "docs/model.md's \(type.name) doesn't name \(member.name)"
                    )
                }
        }
    }
}
