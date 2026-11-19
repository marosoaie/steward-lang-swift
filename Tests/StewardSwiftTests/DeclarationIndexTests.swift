@testable import StewardSwift
import StewardTesting
import Testing

/// The units scopes judge findings by, and the lookups over them.
@Suite("The scopes' units", .timeLimit(.minutes(10)))
struct DeclarationIndexTests {
    @Test("the units are the model's declarations and the top-level items, each with its parent and braces")
    func units() throws {
        let file = try Sample.file("""
            import Foundation

            /// Doc.
            struct S {
                var x: Int {
                    get { 1 }
                }
                func f() {
                    let y = 1
                    func g() {}
                    _ = { let z = y }
                }
            }
            print(1)
            #if DEBUG
            let z = 1
            #endif

            """)
        let units = DeclarationIndex(file: file).units
        #expect(units.map(\.lines) == [1...1, 3...13, 5...7, 8...12, 10...10, 14...14, 16...16])
        #expect(units.map(\.parent) == [nil, nil, 1, 1, 3, nil, nil])
        #expect(units.map(\.body) == [nil, 5...13, nil, nil, nil, nil, nil])
    }

    @Test("braces on one line hold no line, and a member on the line of `{` is outside them")
    func bodies() throws {
        let file = try Sample.file("""
            struct A {}
            struct B { var x = 1
                var y = 2 }

            """)
        let index = DeclarationIndex(file: file)
        #expect(index.units.map(\.body) == [nil, 3...3, nil, nil])
        #expect(index.innermost(containing: 2).flatMap { index.container(of: $0, line: 2) } == nil)
        #expect(index.innermost(containing: 3).flatMap { index.container(of: $0, line: 3) } == 1)
    }

    @Test("this package's files: the lookup is the last unit in source order that holds the line")
    func ownFiles() {
        Self.checkLookups(Corpus.ownFiles)
        Self.checkModelValues(Corpus.ownFiles)
    }

    @Test(
        "swift-argument-parser's files: the lookup is the last unit in source order that holds the line",
        .enabled(if: Corpus.isNetworkAllowed)
    )
    func argumentParserFiles() async throws {
        let files = try await Corpus.argumentParserFiles()
        Self.checkLookups(files)
        Self.checkModelValues(files)
    }

    @Test("what changedDeclarations keeps, changedTypes keeps, on random changes to real files", arguments: 0..<4)
    func nesting(seed: UInt64) throws {
        var generator = SeededGenerator(seed: seed)
        try Corpus.ownFiles.forEach { corpusFile in
            let file = try SwiftFile(source: corpusFile.source, path: corpusFile.path)
            let count = file.sourceLines.count
            let random = { (generator: inout SeededGenerator) in
                LineRangeSet((0..<Int.random(in: 0...4, using: &generator)).map { _ in
                    let start = Int.random(in: 1...count, using: &generator)
                    return start...min(count, start + Int.random(in: 0...3, using: &generator))
                })
            }
            let changed = ChangedFile(
                path: file.path,
                contents: Array(corpusFile.source.utf8),
                changedLines: random(&generator),
                linesAfterDeletions: random(&generator)
            )
            let scoped = SwiftSourceScope.allCases.map { ScopedFindings(file: file, changed: changed, scope: $0) }
            (-1...(count + 1)).forEach { (line: Int) in
                let finding = Finding.message("", at: Location(path: file.path, line: line))
                let kept = scoped.map { $0.keeps(finding) }
                #expect((!kept[0] || kept[1]) && (!kept[1] || kept[2]), "\(file.path):\(line): \(kept)")
            }
        }
    }

    @Test(
        "a declaration's lines up to its name and its `{` are its own, whatever starts on them",
        arguments: [
            ("struct B { var x = 1\n    var y = 2\n    var z = 3\n}\n", 1),
            ("func a() { func b() {}\n    print(1)\n    print(2)\n}\n", 1),
            ("var x = { func inner() {}\n    print(1)\n    print(2)\n}()\n", 1),
            ("@available(*, deprecated)\nvar x = { func inner() {}\n    print(1)\n}()\n", 2),
            ("struct B<T>\n    where T: Equatable { var x = 1\n    var y = 2\n}\n", 1),
            ("var a = 0,\n    b = { func inner() {}\n        return 0\n    }()\n", 2),
            ("let (a,\n     b) = ({ func inner() {}\n    return 0\n}(), 1)\n", 2),
            ("var a = { func helper() {\nfunc inner() {} }; return 0 }(), b =\n    1 +\n    2\n", 2),
        ]
    )
    func header(source: String, line: Int) throws {
        let file = try SwiftFile(source: source, path: Sample.path)
        let index = DeclarationIndex(file: file)
        let keeps = { (line: Int, changed: Int) in
            ScopedFindings(
                path: file.path,
                scope: .changedDeclarations,
                changedLines: LineRangeSet([changed...changed]),
                linesAfterDeletions: LineRangeSet(),
                index: index,
                lineCount: file.sourceLines.count
            ).keeps(.message("", at: Location(path: file.path, line: line)))
        }
        // A finding at the outer declaration is kept when any of its four
        // lines changes; the one that starts on its header is judged with
        // it, the safe side.
        #expect((1...4).allSatisfy { keeps(line, $0) })
        #expect(!keeps(line, 5))
    }

    @Test("siblings that share a line each judge a finding on it")
    func sharedLine() throws {
        // A pull request that adds the attribute changes `a`, not `b`, and
        // both start on line 2.
        let file = try SwiftFile(source: "@MainActor\nfunc a() {}; func b() {}\nfunc c() {}\n", path: Sample.path)
        let index = DeclarationIndex(file: file)
        let scoped = ScopedFindings(
            path: file.path,
            scope: .changedDeclarations,
            changedLines: LineRangeSet([1...1]),
            linesAfterDeletions: LineRangeSet(),
            index: index,
            lineCount: file.sourceLines.count
        )
        #expect(file.functions.map(\.location.line) == [2, 2, 3])
        #expect(file.functions.map { scoped.keeps(.message($0.name, at: $0.location)) } == [true, true, false])
        #expect(index.sharing(try #require(index.innermost(containing: 2)), line: 2).count == 1)
    }

    @Test("a finding at another spelling of the file's path is another file's, as git tells paths apart by bytes")
    func pathBytes() throws {
        let precomposed = "Sources/Caf\u{E9}.swift"
        let decomposed = "Sources/Cafe\u{301}.swift"
        #expect(precomposed == decomposed)
        let file = try SwiftFile(source: "func a() {}\nfunc b() {}\n", path: precomposed)
        let scoped = ScopedFindings(
            file: file,
            changed: ChangedFile(
                path: precomposed,
                contents: [],
                changedLines: LineRangeSet([1...1]),
                linesAfterDeletions: LineRangeSet()
            ),
            scope: .changedDeclarations
        )
        #expect(!scoped.keeps(.message("b", at: Location(path: precomposed, line: 2))))
        #expect(scoped.keeps(.message("b", at: Location(path: decomposed, line: 2))))
    }

    @Test("a file of 20,000 one-line members, each with a finding, is scoped in bounded time")
    func manyUnits() throws {
        let members = (0..<20_000).map { "    var v\($0) = \($0)" }.joined(separator: "\n")
        let source = "struct S {\n\(members)\n}\n"
        let file = try SwiftFile(source: source, path: Sample.path)
        let changed = ChangedFile(
            path: file.path,
            contents: Array(source.utf8),
            changedLines: LineRangeSet((2...20_001).filter { $0.isMultiple(of: 2) }.map { $0...$0 }),
            linesAfterDeletions: LineRangeSet()
        )
        let clock = ContinuousClock()
        var kept = 0
        let elapsed = clock.measure {
            let scoped = ScopedFindings(file: file, changed: changed, scope: .changedDeclarations)
            kept = (1...20_002).count { scoped.keeps(.message("", at: Location(path: file.path, line: $0))) }
        }
        // The struct's own two lines are in it, which changed.
        #expect(kept == 10_000 + 2)
        #expect(elapsed < .seconds(10), "took \(elapsed)")
    }

    /// For every line of each file, `innermost(containing:)` against a
    /// search of every unit; and units in order of their first lines, each
    /// inside its parent.
    private static func checkLookups(_ files: [Corpus.File]) {
        files.forEach { corpusFile in
            let file: SwiftFile
            do {
                file = try SwiftFile(source: corpusFile.source, path: corpusFile.path)
            } catch {
                Issue.record("\(corpusFile.path) was refused: \(error)")
                return
            }
            let index = DeclarationIndex(file: file)
            let units = index.units
            #expect(units.map(\.lines.lowerBound) == units.map(\.lines.lowerBound).sorted(), "\(file.path)")
            #expect(
                units.allSatisfy { unit in
                    unit.parent.map { units[$0].lines.contains(unit.lines.lowerBound) } ?? true
                },
                "\(file.path): a unit starts outside its parent"
            )
            (0...file.sourceLines.count + 1).forEach { line in
                let searched = units.indices.last { units[$0].lines.contains(line) }
                #expect(index.innermost(containing: line) == searched, "\(file.path):\(line)")
            }
        }
    }

    /// For every function, type, member, extension and import: a finding at
    /// its location is kept when any of its lines changes, and not when
    /// only the line after it does.
    private static func checkModelValues(_ files: [Corpus.File]) {
        files.forEach { corpusFile in
            let file: SwiftFile
            do {
                file = try SwiftFile(source: corpusFile.source, path: corpusFile.path)
            } catch {
                Issue.record("\(corpusFile.path) was refused: \(error)")
                return
            }
            let values = file.functions.map { ($0.location, $0.lines) } + file.types.map { ($0.location, $0.lines) }
                + file.memberBlocks.flatMap { $0.members.map { ($0.location, $0.lines) } }
                + file.memberBlocks.map { ($0.location, $0.lines) }
                + file.imports.map { ($0.location, $0.location.line.map { $0...$0 } ?? 1...1) }
            let index = DeclarationIndex(file: file)
            values.forEach { location, lines in
                let finding = Finding.message("", at: location)
                let keeps = { (changed: ClosedRange<Int>) in
                    ScopedFindings(
                        path: file.path,
                        scope: .changedDeclarations,
                        changedLines: LineRangeSet([changed]),
                        linesAfterDeletions: LineRangeSet(),
                        index: index,
                        lineCount: file.sourceLines.count
                    ).keeps(finding)
                }
                let what = "\(file.path):\(location.line ?? 0), lines \(lines)"
                #expect(keeps(lines.lowerBound...lines.lowerBound), "\(what): its first line changed")
                #expect(keeps(lines.upperBound...lines.upperBound), "\(what): its last line changed")
                #expect(!keeps(lines.upperBound + 1...lines.upperBound + 1), "\(what): the line after it changed")
            }
        }
    }
}

/// The index's cost on dense and deeply nested files.
extension DeclarationIndexTests {
    @Test("thousands of declarations on one line, each with a finding, are scoped in bounded time")
    func manyOnOneLine() throws {
        let source = (0..<20_000).map { "var v\($0) = \($0)" }.joined(separator: "; ") + "\n"
        let file = try SwiftFile.read(source: source, path: Sample.path, timeLimit: .seconds(300), gate: ParseGate())
        let scoped = ScopedFindings(
            path: file.path,
            scope: .changedDeclarations,
            changedLines: LineRangeSet(),
            linesAfterDeletions: LineRangeSet(),
            index: DeclarationIndex(file: file),
            lineCount: file.sourceLines.count
        )
        let findings = (0..<20_000).map { Finding.message("v\($0)", at: Location(path: file.path, line: 1)) }
        let clock = ContinuousClock()
        var kept: [Finding] = []
        let elapsed = clock.measure { kept = scoped.kept(findings) }
        #expect(kept.isEmpty)
        // Judged once for the line: a judgment for each finding would walk
        // 20,000 siblings 20,000 times.
        #expect(elapsed < .seconds(2), "took \(elapsed)")
    }

    @Test("items under ninety-five nested #if blocks are indexed about as fast as the same items under none")
    func deepConditionalCompilation() throws {
        // A gate and a limit of the test's own: under a loaded run's other
        // tests, this read can outlast its deadline, and a runaway on the
        // shared gate would refuse every later read in the process.
        let read = { (depth: Int) throws -> SwiftFile in
            let items = String(repeating: "f()\n", count: 20_000)
            let source = String(repeating: "#if A\n", count: depth) + items
                + String(repeating: "#endif\n", count: depth)
            return try SwiftFile.read(source: source, path: Sample.path, timeLimit: .seconds(300), gate: ParseGate())
        }
        let (flat, deep) = (try read(0), try read(95))
        // The faster of three, each way, to see past a loaded machine. The
        // walk this replaced took about six times as long under 95 `#if`s.
        let clock = ContinuousClock()
        let time = { (file: SwiftFile) in
            (0..<3).map { _ in clock.measure { _ = DeclarationIndex(file: file) } }.min() ?? .zero
        }
        #expect(DeclarationIndex(file: deep).units.count == 20_000)
        let (flatTime, deepTime) = (time(flat), time(deep))
        #expect(deepTime < flatTime * 2 + .milliseconds(100), "\(deepTime) under 95 #if, \(flatTime) under none")
    }
}
