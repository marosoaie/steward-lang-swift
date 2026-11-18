import Foundation
import StewardSwift
import Testing

/// Real files, whole, cut short and mutated: nothing traps, every parse
/// takes bounded time, and what's read stays inside the file.
@Suite("Robustness", .timeLimit(.minutes(10)))
struct RobustnessTests {
    /// The longest any one parse here may take. Generous: a debug build on
    /// a CI runner parses a 50 KB file in well under a second.
    static let parseBudget = Duration.seconds(10)

    @Test("this package's own files read in full, with every written func found")
    func ownFiles() {
        Self.checkWhole(Corpus.ownFiles)
    }

    @Test(
        "swift-argument-parser's files read in full, with every written func found",
        .enabled(if: Corpus.isNetworkAllowed)
    )
    func argumentParserFiles() async throws {
        let files = try await Corpus.argumentParserFiles()
        #expect(files.count > 100)
        Self.checkWhole(files)
    }

    @Test(
        "a file cut short anywhere reads without trapping, even inside a character",
        .enabled(if: Corpus.isNetworkAllowed),
        arguments: 0..<4
    )
    func truncations(batch: Int) async throws {
        let files = try await Corpus.argumentParserFiles() + Corpus.ownFiles
        // A quarter of the files per batch, cut at seven places each, and
        // inside the first multi-byte character if there is one.
        files.enumerated().filter { $0.offset % 4 == batch }.map(\.element).forEach { file in
            let bytes = Array(file.source.utf8)
            let cuts = (1...7).map { bytes.count * $0 / 8 } + [bytes.firstIndex { $0 >= 0xC0 }.map { $0 + 1 } ?? 0]
            cuts.forEach { cut in
                let source = String(decoding: bytes.prefix(cut), as: UTF8.self)
                Self.check(source: source, path: file.path, what: "\(file.path) cut at \(cut)")
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
        (batch * 16..<(batch + 1) * 16).forEach { seed in
            var generator = SeededGenerator(seed: seed)
            guard let file = files.randomElement(using: &generator) else { return }
            let count = Int.random(in: 1...32, using: &generator)
            let bytes = Mutation.apply(count: count, to: Array(file.source.utf8), using: &generator)
            let source = String(decoding: bytes, as: UTF8.self)
            Self.check(source: source, path: file.path, what: "seed \(seed), \(file.path)")
        }
    }

    private static func checkWhole(_ files: [Corpus.File]) {
        files.forEach { file in
            guard case .success(let parsed) = check(source: file.source, path: file.path, what: file.path) else {
                Issue.record("\(file.path) was refused")
                return
            }
            #expect(parsed.syntax.description == file.source, "\(file.path) doesn't read back as written")
            #expect(
                Invariants.functionsWithWrittenKeyword(in: parsed) == Invariants.writtenFunctionKeywords(in: parsed),
                "\(file.path): the walk and swift-syntax's tokens disagree"
            )
        }
    }

    /// Reads `source` within the budget. A file that's read keeps the
    /// invariants; a refusal is an outcome too, but never a trap.
    @discardableResult
    private static func check(source: String, path: String, what: String) -> Result<SwiftFile, SwiftFile.Refusal> {
        let clock = ContinuousClock()
        var outcome: Result<SwiftFile, SwiftFile.Refusal>?
        let elapsed = clock.measure {
            outcome = Result { () throws(SwiftFile.Refusal) in try SwiftFile(source: source, path: path) }
        }
        #expect(elapsed < parseBudget, "\(what) took \(elapsed)")
        if case .success(let file) = outcome {
            Invariants.check(file, source: source)
        }
        return outcome ?? .failure(.earlierParseStillRunning)
    }
}
