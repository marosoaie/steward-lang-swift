import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real Swift files: this package's own sources, and swift-argument-parser's
/// at a pinned release, downloaded once and cached.
///
/// The cache is `~/Library/Caches/steward-lang-swift-tests/` on macOS and
/// `${XDG_CACHE_HOME:-~/.cache}/steward-lang-swift-tests/` on Linux.
/// `STEWARD_SWIFT_SKIP_NETWORK_TESTS=1` leaves the download out, and with
/// it every test that needs it.
enum Corpus {
    /// A file, with the path a pull request would give it.
    struct File: Sendable, CustomStringConvertible {
        var path: String
        var source: String

        var description: String { path }
    }

    static let argumentParserTag = "1.8.2"

    static var isNetworkAllowed: Bool {
        ProcessInfo.processInfo.environment["STEWARD_SWIFT_SKIP_NETWORK_TESTS"] != "1"
    }

    /// This package's `Sources` and `Tests`, found from this file's path.
    static let ownFiles: [File] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return swiftFiles(under: root, in: ["Sources", "Tests"])
    }()

    /// swift-argument-parser's Swift files: its sources, tests, examples and
    /// tools.
    static func argumentParserFiles() async throws -> [File] {
        swiftFiles(under: try await argumentParser.value, in: ["."])
    }

    /// The checkout's root, downloaded on first use. One task, so tests
    /// running in parallel share a download.
    static let argumentParser = Task<URL, any Error> {
        let name = "swift-argument-parser-\(argumentParserTag)"
        let tree = cacheDirectory.appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: tree.appendingPathComponent("Package.swift").path) {
            return tree
        }
        let url = "https://codeload.github.com/apple/swift-argument-parser/tar.gz/refs/tags/\(argumentParserTag)"
        guard let remote = URL(string: url) else { throw CorpusError("bad URL \(url)") }
        let archive = try await download(remote)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        // Extracted next to the cache and moved in whole, so a killed run
        // can't leave half a tree, and a test process that loses the race
        // uses the one that won.
        let staging = cacheDirectory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let archiveFile = staging.appendingPathComponent("archive.tar.gz")
        try archive.write(to: archiveFile)
        try run(["tar", "-xzf", archiveFile.path, "-C", staging.path])
        let extracted = staging.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: extracted.appendingPathComponent("Package.swift").path) else {
            throw CorpusError("\(url) didn't hold \(name)/Package.swift; delete \(cacheDirectory.path) and re-run")
        }
        do {
            try FileManager.default.moveItem(at: extracted, to: tree)
        } catch where FileManager.default.fileExists(atPath: tree.appendingPathComponent("Package.swift").path) {
            // Another process moved its copy in first.
        }
        return tree
    }

    static let cacheDirectory: URL = {
        let environment = ProcessInfo.processInfo.environment
        #if canImport(Darwin)
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        #else
        let root = environment["XDG_CACHE_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? URL(fileURLWithPath: environment["HOME"] ?? NSHomeDirectory()).appendingPathComponent(".cache")
        #endif
        return root.appendingPathComponent("steward-lang-swift-tests", isDirectory: true)
    }()

    private static func swiftFiles(under root: URL, in directories: [String]) -> [File] {
        directories.flatMap { directory -> [File] in
            let base = root.appendingPathComponent(directory)
            let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
            return (enumerator?.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "swift" }
                .map { url in
                    let rootPath = root.standardizedFileURL.path
                    let relative = String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))
                    let data = (try? Data(contentsOf: url)) ?? Data()
                    return File(path: relative, source: String(decoding: data, as: UTF8.self))
                }
        }
        .sorted { $0.path < $1.path }
    }

    private static func download(_ url: URL) async throws -> Data {
        var lastError: (any Error)?
        for attempt in 1...3 {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, !data.isEmpty else {
                    throw CorpusError("GET \(url) returned status \(status)")
                }
                return data
            } catch {
                lastError = error
                if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
            }
        }
        throw CorpusError("couldn't download \(url): \(lastError.map(String.init(describing:)) ?? "unknown error")")
    }

    private static func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CorpusError("\(arguments.joined(separator: " ")) exited with status \(process.terminationStatus)")
        }
    }
}

struct CorpusError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
