import Foundation
import StewardSwift
import StewardTesting
import Testing

/// The model against the compiler: every function swift-argument-parser's
/// symbol graph lists, at minimum access level `private`, is read at the
/// same line with the same name and argument labels, `async`, `throws`,
/// access level and `static`; every function, type and member it lists,
/// with the same doc comment; and every property and global variable, as
/// a `let` or a `var`, stored or not where the graph shows it, with the
/// type it writes.
///
/// What the corpus doesn't exercise: the graph lists no local functions,
/// and no function in it takes its access level from an extension's
/// modifier, so those parts of `AccessLevel` are held by unit tests only.
/// Only 9 of its 345 functions are `async`, and few are protocol
/// requirements. None of its doc comments is a `/** */` block, so
/// `DocumentationShape`'s shapes, compiled into a package of their own,
/// hold those, and the other shapes of a doc comment. Outside extensions,
/// the types around a declaration lower its level only to `private` (25
/// of the values compared, from `internal` or `fileprivate`), never a
/// `public` one to `internal`: that case, the one steward-lang-swift#27
/// starts from, is held by `EffectiveAccessTests` alone.
@Suite("Symbol graph oracle", .enabled(if: SymbolGraphOracle.isEnabled), .timeLimit(.minutes(20)))
struct SymbolGraphOracleTests {
    @Test("every function in the compiler's symbol graph is read alike")
    func functionsMatchTheSymbolGraph() async throws {
        let graph = try await SymbolGraphOracle.graph.value
        #expect(graph.functions.count > 300, "the graph listed only \(graph.functions.count) functions with a location")
        // With synthesized copies left out, no function should be listed
        // twice; one that is would hide an overload.
        let twice = Dictionary(grouping: graph.functions) { "\($0.path):\($0.line) \($0.title)" }
            .filter { $0.value.count > 1 }
        #expect(twice.isEmpty, "listed more than once: \(twice.keys.sorted())")
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

    @Test("every symbol's doc comment in the compiler's symbol graph is read alike")
    func documentationMatchesTheSymbolGraph() async throws {
        let graph = try await SymbolGraphOracle.graph.value
        #expect(graph.documented.filter { $0.documentation != nil }.count > 500)
        let byFile = Dictionary(grouping: graph.documented, by: \.path)
        let differences = try byFile.keys.sorted().flatMap { path -> [String] in
            let data = try Data(contentsOf: graph.root.appendingPathComponent(path))
            let file = try SwiftFile(source: String(decoding: data, as: UTF8.self), path: path)
            return (byFile[path] ?? []).filter { !Self.isBoundByStatement($0, in: file) }
                .compactMap { expected in Self.documentationDifference(expected, in: file) }
        }
        #expect(
            differences.isEmpty,
            "\(differences.count) differences:\n\(differences.prefix(40).joined(separator: "\n"))"
        )
    }

    @Test("every doc comment shape is read as the compiler reads it, and as the shape says")
    func shapesMatchTheCompiler() throws {
        let shapes = DocumentationShape.all
        let source = shapes.indices.map { shapes[$0].source(naming: "shape\($0)") }.joined(separator: "\n\n")
        let compiler = try SymbolGraphOracle.documentation(ofSymbolsIn: source)
        let file = try SwiftFile(source: source, path: "Shapes.swift")
        let differences = shapes.indices.compactMap { index -> String? in
            let name = "shape\(index)"
            let model = file.functions.first { $0.name == name }?.documentation
            guard let compiled = compiler[name] else { return "\(name): not in the graph" }
            guard compiled == shapes[index].text, model == compiled else {
                let texts = [compiled, shapes[index].text, model].map(\.debugDescription)
                return "\(name): compiler \(texts[0]), shape \(texts[1]), read \(texts[2])"
            }
            return nil
        }
        #expect(differences.isEmpty, "\(differences.joined(separator: "\n"))")
    }

    @Test("every property and global in the compiler's symbol graph is a let or a var, stored or not, typed as written")
    func propertiesMatchTheSymbolGraph() async throws {
        let graph = try await SymbolGraphOracle.graph.value
        let kinds: Set = ["swift.property", "swift.type.property", "swift.var"]
        let properties = graph.documented.filter { kinds.contains($0.kind) }
        #expect(properties.count > 600)
        let byFile = Dictionary(grouping: properties, by: \.path)
        let read = try byFile.keys.sorted().map { path -> (differences: [String], counts: (globals: Int, bound: Int)) in
            let data = try Data(contentsOf: graph.root.appendingPathComponent(path))
            let file = try SwiftFile(source: String(decoding: data, as: UTF8.self), path: path)
            let members = file.memberBlocks.flatMap(\.members) + file.topLevelMembers
            let expected = byFile[path] ?? []
            let bound = expected.filter { Self.isBoundByStatement($0, in: file) }
            let differences = expected.filter { !Self.isBoundByStatement($0, in: file) }.compactMap { expected in
                let atLine = members.first { $0.location.line == expected.line && $0.name == expected.name }
                guard let member = atLine, let property = member.property else { return "\(expected): not read" }
                return Self.propertyDifference(property, of: member, expected)
            }
            let globals = file.topLevelMembers.filter { member in
                expected.contains { $0.line == member.location.line && $0.name == member.name }
            }
            return (differences, (globals.count, bound.count))
        }
        let differences = read.flatMap(\.differences)
        // The corpus's globals: six declared, and the two that
        // Examples/roll/main.swift's `for` binds, which the graph lists too.
        let (globals, bound) = (read.map(\.counts.globals).reduce(0, +), read.map(\.counts.bound).reduce(0, +))
        #expect(globals == 6 && bound == 2, "\(globals) globals read, \(bound) bound by statements")
        #expect(
            differences.isEmpty,
            "\(differences.count) differences:\n\(differences.prefix(40).joined(separator: "\n"))"
        )
    }

    /// Whether `expected` is a variable that a statement at the top of the
    /// file binds, such as a `for` loop's in a `main.swift`: the graph
    /// lists it as a global, and the model, which reads declarations,
    /// doesn't (the corpus has two, in Examples/roll/main.swift).
    static func isBoundByStatement(_ expected: SymbolGraphOracle.Documented, in file: SwiftFile) -> Bool {
        expected.kind == "swift.var" && file.syntax.statements.contains { item in
            guard !item.item.is(DeclSyntax.self), let first = file.location(of: item).line,
                  let last = item.lastToken(viewMode: .sourceAccurate).flatMap({ file.location(of: $0).line })
            else { return false }
            return (first...last).contains(expected.line)
        }
    }

    @Test("every declaration's effective access level is the compiler's, but for what an extension holds")
    func effectiveAccessMatchesTheSymbolGraph() async throws {
        let graph = try await SymbolGraphOracle.graph.value
        let byFile = Dictionary(grouping: graph.documented.filter { $0.effectiveAccess != nil }, by: \.path)
        let read = try byFile.keys.sorted().flatMap { path -> [EffectiveRead] in
            let data = try Data(contentsOf: graph.root.appendingPathComponent(path))
            let file = try SwiftFile(source: String(decoding: data, as: UTF8.self), path: path)
            return (byFile[path] ?? []).filter { !Self.isBoundByStatement($0, in: file) }
                .map { Self.effectiveRead($0, in: file) }
        }
        let differences = read.flatMap(\.differences)
        let (compared, inExtensions) = (read.map(\.compared).reduce(0, +), read.map(\.inExtensions).reduce(0, +))
        let lowered = read.map(\.lowered).reduce(0, +)
        #expect(
            compared > 1_000 && inExtensions > 100 && lowered > 0,
            "compared \(compared), in extensions \(inExtensions), lowered by the types around them \(lowered)"
        )
        #expect(
            differences.isEmpty,
            "\(differences.count) differences:\n\(differences.prefix(40).joined(separator: "\n"))"
        )
    }

    /// How the model's values at a symbol's line, with its name, read its
    /// effective level against the graph's: those in an extension, which
    /// doesn't cap them, are counted and not compared, and those compared
    /// whose level the types around them lowered are counted.
    struct EffectiveRead {
        var compared = 0
        var inExtensions = 0
        var lowered = 0
        var differences: [String] = []
    }

    /// A model value's node, its own level and its effective level.
    struct Levels {
        var syntax: Syntax
        var declared: AccessLevel.Level
        var effective: AccessLevel.Level
    }

    static func effectiveRead(_ expected: SymbolGraphOracle.Documented, in file: SwiftFile) -> EffectiveRead {
        let atLine = { (location: Location, name: String) in location.line == expected.line && name == expected.name }
        let values: [Levels] =
            file.functions.filter { atLine($0.location, $0.name) }
                .map { Levels(syntax: Syntax($0.syntax), declared: $0.access.level, effective: $0.effectiveAccess) }
            + file.types.filter { atLine($0.location, $0.name) }
                .map { Levels(syntax: Syntax($0.syntax), declared: $0.access.level, effective: $0.effectiveAccess) }
            + (file.memberBlocks.flatMap(\.members) + file.topLevelMembers).filter { atLine($0.location, $0.name) }
                .map { Levels(syntax: Syntax($0.syntax), declared: $0.access.level, effective: $0.effectiveAccess) }
        guard !values.isEmpty else {
            return EffectiveRead(differences: ["\(expected): not read"])
        }
        let isInExtension = { (node: Syntax) in
            sequence(first: node, next: \.parent).contains { $0.is(ExtensionDeclSyntax.self) }
        }
        let compared = values.filter { !isInExtension($0.syntax) }
        let differences = compared.filter { $0.effective != expected.effectiveAccess }.map {
            "\(expected): read \($0.effective), compiler \(expected.effectiveAccess.map { "\($0)" } ?? "?")"
        }
        return EffectiveRead(
            compared: compared.count,
            inExtensions: values.count - compared.count,
            lowered: compared.filter { $0.effective < $0.declared }.count,
            differences: differences
        )
    }

    /// What the model reads differently from the graph's declaration of a
    /// property, or nil. The graph prints the type it infers, so the type
    /// is compared only where the source writes one. It prints `{ get }` or
    /// `{ get set }` after a property that isn't stored, but also after
    /// some that are, as written, for which storage isn't compared: one
    /// with an attribute it prints first (`@Option var …`, a property
    /// wrapper among them, whose storage the wrapper replaces), one whose
    /// setter is less visible (`private(set)`, `{ get }`), and a `lazy`
    /// one. It prints `{ get set }` after one with `willSet` or `didSet`
    /// too, which the corpus has none of; a corpus that has one would show
    /// here as a difference.
    static func propertyDifference(
        _ property: Member.Property,
        of member: Member,
        _ expected: SymbolGraphOracle.Documented
    ) -> String? {
        let isConstant: Bool = expected.keywords.contains("let")
        let showsStorage = !expected.declaration.hasPrefix("@")
            && !member.modifiers.contains { $0.hasSuffix("(set)") || $0 == "lazy" }
        let isStored: Bool = showsStorage ? !expected.declaration.hasSuffix("}") : property.isStored
        let afterColon: Substring = expected.declaration.split(separator: ": ", maxSplits: 1).dropFirst().first ?? ""
        let printedType = String(afterColon.split(separator: " {", maxSplits: 1).first ?? afterColon)
        let constantDifference: String? = property.isConstant == isConstant
            ? nil : "let: read \(property.isConstant), compiler \(isConstant)"
        let storedDifference: String? = property.isStored == isStored
            ? nil : "stored: read \(property.isStored), compiler \(isStored)"
        let typeDifference: String? = property.type.flatMap { type in
            type == TypeName(printedType) ? nil : "type: read \(type), compiler \(printedType)"
        }
        let differing = [constantDifference, storedDifference, typeDifference].compactMap { $0 }
        return differing.isEmpty ? nil : "\(expected) `\(expected.declaration)`: \(differing.joined(separator: ", "))"
    }

    /// What the model reads differently from the graph for `expected`'s doc
    /// comment, or nil when every value at its line with its name reads it
    /// alike: a function, a type, a member or top-level member, and a
    /// type's member block.
    static func documentationDifference(_ expected: SymbolGraphOracle.Documented, in file: SwiftFile) -> String? {
        let atLine = { (location: Location, name: String) in location.line == expected.line && name == expected.name }
        let functions = file.functions.filter { atLine($0.location, $0.name) }.map(\.documentation)
        let types = file.types.filter { atLine($0.location, $0.name) }.map(\.documentation)
        let members = (file.memberBlocks.flatMap(\.members) + file.topLevelMembers)
            .filter { atLine($0.location, $0.name) }.map(\.documentation)
        let blocks = file.memberBlocks.filter { block in
            guard case .type(_, let name) = block.owner else { return false }
            return atLine(block.location, name)
        }
        let read: [String?] = functions + types + members + blocks.map(\.documentation)
        if read.isEmpty {
            return "\(expected): not read"
        }
        let differing = read.filter { $0 != expected.documentation }
        guard let first = differing.first else { return nil }
        return "\(expected): read \(first.debugDescription), compiler \(expected.documentation.debugDescription)"
    }

    /// What the model reads differently from the graph for `expected`, or
    /// nil when it reads the same.
    static func difference(_ expected: SymbolGraphOracle.Function, in file: SwiftFile) -> String? {
        let atLine = file.functions.filter { $0.location.line == expected.line }
        guard let function = atLine.first(where: { $0.name == expected.name }) else {
            return "\(expected): not read (at that line: \(atLine.map(\.name)))"
        }
        let differing = [
            ("title", Self.title(of: function), expected.title),
            ("access", "\(function.access.level)", expected.access.map(String.init(describing:)) ?? "?"),
            ("async", "\(function.isAsync)", "\(expected.isAsync)"),
            ("throws", "\(function.isThrowing)", "\(expected.isThrowing)"),
            ("static", "\(function.isStatic)", "\(expected.isStatic)"),
        ]
        .filter { $0.1 != $0.2 }
        .map { "\($0.0): read \($0.1), compiler \($0.2)" }
        return differing.isEmpty ? nil : "\(expected): \(differing.joined(separator: ", "))"
    }

    /// The function's name with its argument labels, as the graph titles
    /// it: `parse(_:into:)`. An operator's parameters have no labels.
    static func title(of function: FunctionDeclaration) -> String {
        let isOperator = function.syntax.name.identifier == nil
        let labels = function.parameters.map { (isOperator ? nil : $0.label) ?? "_" }
        return "\(function.name)(\(labels.map { "\($0):" }.joined()))"
    }
}
