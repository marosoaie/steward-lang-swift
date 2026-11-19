import Foundation
@testable import StewardSwift
import Testing

/// Real files, whole, cut short and mutated: nothing traps, every parse
/// takes bounded time, and what's read stays inside the file.
@Suite("Robustness", .timeLimit(.minutes(10)))
struct RobustnessTests {
    /// The longest any one parse here may take. Generous: a debug build on
    /// a CI runner parses a 50 KB file in well under a second.
    static let parseBudget = Duration.seconds(10)

    @Test("this package's own files read in full, with every written func found")
    func ownFiles() async {
        await Self.checkWhole(Corpus.ownFiles)
    }

    @Test(
        "swift-argument-parser's files read in full, with every written func found",
        .enabled(if: Corpus.isNetworkAllowed)
    )
    func argumentParserFiles() async throws {
        let files = try await Corpus.argumentParserFiles()
        #expect(files.count > 100)
        await Self.checkWhole(files)
    }

    @Test(
        "a file cut short anywhere reads without trapping, even inside a character",
        .enabled(if: Corpus.isNetworkAllowed),
        arguments: 0..<4
    )
    func truncations(batch: Int) async throws {
        let files = try await Corpus.argumentParserFiles() + Corpus.ownFiles
        // A quarter of the files per batch, cut at seven places each, and
        // inside the first multi-byte character if there is one. Imperative
        // loops, since each read is awaited.
        for file in files.enumerated().filter({ $0.offset % 4 == batch }).map(\.element) {
            let bytes = Array(file.source.utf8)
            let cuts = (1...7).map { bytes.count * $0 / 8 } + [bytes.firstIndex { $0 >= 0xC0 }.map { $0 + 1 } ?? 0]
            for cut in cuts {
                let source = String(decoding: bytes.prefix(cut), as: UTF8.self)
                await Self.check(source: source, path: file.path, what: "\(file.path) cut at \(cut)")
            }
        }
    }

    @Test(
        "seeded byte mutations of real files read without trapping",
        .enabled(if: Corpus.isNetworkAllowed),
        arguments: 0..<16
    )
    func mutations(batch: UInt64) async throws {
        let files = try await Corpus.argumentParserFiles()
        // An imperative loop, since each read is awaited.
        for seed in batch * 16..<(batch + 1) * 16 {
            var generator = SeededGenerator(seed: seed)
            guard let file = files.randomElement(using: &generator) else { continue }
            let count = Int.random(in: 1...32, using: &generator)
            let bytes = Mutation.apply(count: count, to: Array(file.source.utf8), using: &generator)
            let source = String(decoding: bytes, as: UTF8.self)
            await Self.check(source: source, path: file.path, what: "seed \(seed), \(file.path)")
        }
    }

    private static func checkWhole(_ files: [Corpus.File]) async {
        // An imperative loop, since each read is awaited.
        for file in files {
            guard case .success(let parsed) = await check(source: file.source, path: file.path, what: file.path) else {
                Issue.record("\(file.path) was refused")
                continue
            }
            #expect(parsed.syntax.description == file.source, "\(file.path) doesn't read back as written")
            #expect(
                Invariants.functionsWithWrittenKeyword(in: parsed) == Invariants.writtenFunctionKeywords(in: parsed),
                "\(file.path): the walk and swift-syntax's tokens disagree"
            )
        }
    }

    /// Reads `source`, and indexes it for the scopes, within the budget. A
    /// file that's read keeps the invariants; a refusal is an outcome too,
    /// but never a trap.
    @discardableResult
    private static func check(
        source: String,
        path: String,
        what: String
    ) async -> Result<SwiftFile, SwiftFile.Refusal> {
        let clock = ContinuousClock()
        let start = clock.now
        let outcome: Result<SwiftFile, SwiftFile.Refusal>
        do throws(SwiftFile.Refusal) {
            outcome = .success(try await SwiftFile(source: source, path: path))
        } catch {
            outcome = .failure(error)
        }
        // The scopes' index, and a lookup at every line, as for a rule that
        // reports on each.
        if case .success(let file) = outcome {
            let index = DeclarationIndex(file: file)
            (0...(file.sourceLines.count + 1)).forEach { (line: Int) in
                _ = index.innermost(containing: line).flatMap { index.container(of: $0, line: line) }
            }
        }
        let elapsed = start.duration(to: clock.now)
        #expect(elapsed < parseBudget, "\(what) took \(elapsed)")
        if case .success(let file) = outcome {
            Invariants.check(file, source: source)
            Invariants.checkDeclarations(file, source: source)
        }
        return outcome
    }
}
