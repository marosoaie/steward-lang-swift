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
        #expect(units.map(\.lineRange) == [1...1, 3...13, 5...7, 8...12, 10...10, 14...14, 16...16])
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
                changedLineNumbers: random(&generator),
                lineNumbersAfterDeletions: random(&generator)
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
        "a line is every declaration's that has a token of its own on it, whatever else starts there",
        arguments: [
            ("struct B { var x = 1\n    var y = 2\n    var z = 3\n}\n", 1),
            ("func a() { func b() {}\n    print(1)\n    print(2)\n}\n", 1),
            ("var x = { func inner() {}\n    print(1)\n    print(2)\n}()\n", 1),
            ("@available(*, deprecated)\nvar x = { func inner() {}\n    print(1)\n}()\n", 2),
            ("struct B<T>\n    where T: Equatable { var x = 1\n    var y = 2\n}\n", 1),
            ("var a = 0,\n    b = { func inner() {}\n        return 0\n    }()\n", 2),
            ("let (a,\n     b) = ({ func inner() {}\n    return 0\n}(), 1)\n", 2),
            ("var a = { func helper() {\nfunc inner() {} }; return 0 }(), b =\n    1 +\n    2\n", 2),
            ("var a = {\n    struct Local {\n    }; return 0 }(), b =\n    0\n", 3),
        ]
    )
    func header(source: String, line: Int) throws {
        let file = try SwiftFile(source: source, path: Sample.path)
        let index = DeclarationIndex(file: file)
        let keeps = { (line: Int, changed: Int) in
            ScopedFindings(
                path: file.path,
                scope: .changedDeclarations,
                changedLineNumbers: LineRangeSet([changed...changed]),
                lineNumbersAfterDeletions: LineRangeSet(),
                index: index,
                lineCount: file.sourceLines.count
            ).keeps(.message("", at: Location(path: file.path, line: line)))
        }
        // A finding at the outer declaration is kept when any of its four
        // lines changes; the one that shares its line is judged with it,
        // the safe side.
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
            changedLineNumbers: LineRangeSet([1...1]),
            lineNumbersAfterDeletions: LineRangeSet(),
            index: index,
            lineCount: file.sourceLines.count
        )
        #expect(file.functions.map(\.location.line) == [2, 2, 3])
        #expect(file.functions.map { scoped.keeps(.message($0.name, at: $0.location)) } == [true, true, false])
        #expect(index.units(judging: 2).count == 2)
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
                changedLineNumbers: LineRangeSet([1...1]),
                lineNumbersAfterDeletions: LineRangeSet()
            ),
            scope: .changedDeclarations
        )
        #expect(!scoped.keeps(.message("b", at: Location(path: precomposed, line: 2))))
        #expect(scoped.keeps(.message("b", at: Location(path: decomposed, line: 2))))
    }

    @Test("one-line members, each with a finding, are scoped in linear time: 20,000 take under seven times 5,000's")
    func manyUnits() throws {
        // A gate and a limit of the test's own, as below: what's timed is
        // the scoping, and under a loaded run's other tests a read can
        // outlast its deadline, which would refuse every later read on the
        // shared gate.
        let scoping = { (count: Int) throws -> () -> Int in
            let members = (0..<count).map { "    var v\($0) = \($0)" }.joined(separator: "\n")
            let source = "struct S {\n\(members)\n}\n"
            let file = try SwiftFile.read(
                source: source, path: Sample.path, timeLimit: .seconds(300), gate: ParseGate()
            )
            let changed = ChangedFile(
                path: file.path,
                contents: Array(source.utf8),
                changedLineNumbers: LineRangeSet((2...count + 1).filter { $0.isMultiple(of: 2) }.map { $0...$0 }),
                lineNumbersAfterDeletions: LineRangeSet()
            )
            return {
                let scoped = ScopedFindings(file: file, changed: changed, scope: .changedDeclarations)
                return (1...count + 2).count { scoped.keeps(.message("", at: Location(path: file.path, line: $0))) }
            }
        }
        let (quarter, full) = (try scoping(5_000), try scoping(20_000))
        // The struct's own two lines are in it, which changed.
        #expect(full() == 10_000 + 2)
        // The faster of five, each way, taken in turns, as below. Linear
        // scoping takes four times as long for four times the members; a
        // judgment of each finding against every unit would take sixteen.
        // Seven is between them, with room either way for a loaded run.
        let clock = ContinuousClock()
        let rounds = (0..<5).map { _ in (clock.measure { _ = quarter() }, clock.measure { _ = full() }) }
        let (quarterTime, fullTime) = (rounds.map(\.0).min() ?? .zero, rounds.map(\.1).min() ?? .zero)
        #expect(fullTime < quarterTime * 7, "\(fullTime) for 20,000 members, \(quarterTime) for 5,000")
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
            #expect(units.map(\.lineRange.lowerBound) == units.map(\.lineRange.lowerBound).sorted(), "\(file.path)")
            #expect(
                units.allSatisfy { unit in
                    unit.parent.map { units[$0].lineRange.contains(unit.lineRange.lowerBound) } ?? true
                },
                "\(file.path): a unit starts outside its parent"
            )
            (0...file.sourceLines.count + 1).forEach { line in
                let searched = units.indices.last { units[$0].lineRange.contains(line) }
                #expect(index.innermost(containing: line) == searched, "\(file.path):\(line)")
            }
        }
    }

    /// For every function, type, member, top-level member, extension and
    /// import: a finding at its location is kept when any of its lines
    /// changes, and not when only the line after it does.
    private static func checkModelValues(_ files: [Corpus.File]) {
        files.forEach { corpusFile in
            let file: SwiftFile
            do {
                file = try SwiftFile(source: corpusFile.source, path: corpusFile.path)
            } catch {
                Issue.record("\(corpusFile.path) was refused: \(error)")
                return
            }
            let values = file.functions.map { ($0.location, $0.lineRange) }
                + file.types.map { ($0.location, $0.lineRange) }
                + file.memberBlocks.flatMap { $0.members.map { ($0.location, $0.lineRange) } }
                + file.topLevelMembers.map { ($0.location, $0.lineRange) }
                + file.memberBlocks.map { ($0.location, $0.lineRange) }
                + file.imports.map { ($0.location, $0.location.line.map { $0...$0 } ?? 1...1) }
            let index = DeclarationIndex(file: file)
            values.forEach { location, lineRange in
                let finding = Finding.message("", at: location)
                let keeps = { (changed: ClosedRange<Int>) in
                    ScopedFindings(
                        path: file.path,
                        scope: .changedDeclarations,
                        changedLineNumbers: LineRangeSet([changed]),
                        lineNumbersAfterDeletions: LineRangeSet(),
                        index: index,
                        lineCount: file.sourceLines.count
                    ).keeps(finding)
                }
                let what = "\(file.path):\(location.line ?? 0), lines \(lineRange)"
                #expect(keeps(lineRange.lowerBound...lineRange.lowerBound), "\(what): its first line changed")
                #expect(keeps(lineRange.upperBound...lineRange.upperBound), "\(what): its last line changed")
                let after = lineRange.upperBound + 1
                #expect(!keeps(after...after), "\(what): the line after it changed")
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
            changedLineNumbers: LineRangeSet(),
            lineNumbersAfterDeletions: LineRangeSet(),
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
        // The faster of five, each way, taken in turns, so that a loaded
        // machine slows both alike: timed one way and then the other, the
        // load a run's other tests put on the machine fell on one and not
        // the other, and the two seemed twice as far apart as they are.
        // Unloaded, they take about as long; the walk this replaced took
        // about six times as long under 95 `#if`s.
        let clock = ContinuousClock()
        let rounds = (0..<5).map { _ in
            (clock.measure { _ = DeclarationIndex(file: flat) }, clock.measure { _ = DeclarationIndex(file: deep) })
        }
        #expect(DeclarationIndex(file: deep).units.count == 20_000)
        let (flatTime, deepTime) = (rounds.map(\.0).min() ?? .zero, rounds.map(\.1).min() ?? .zero)
        #expect(deepTime < flatTime * 2 + .milliseconds(100), "\(deepTime) under 95 #if, \(flatTime) under none")
    }
}
