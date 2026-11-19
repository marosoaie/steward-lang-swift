import Foundation

/// A process run to its end, with its standard output and error.
struct Subprocess {
    var status: Int32
    /// Whether it exited or was killed by a signal, `status`'s.
    var reason: Process.TerminationReason
    var output: String
    var error: String

    /// Runs `executable` with `arguments` in `directory`, with exactly
    /// `environment`, and waits for it to end.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        in directory: URL
    ) throws -> Subprocess {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        // Files rather than pipes, so neither stream can fill up and block
        // the process while the other is drained.
        let streams = try ["stdout", "stderr"].map { name in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("steward-lang-swift-tests-\(UUID().uuidString).\(name)")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw SubprocessError("couldn't create \(url.path) for \(executable.lastPathComponent)'s \(name)")
            }
            return (url: url, handle: try FileHandle(forWritingTo: url))
        }
        defer {
            streams.forEach { stream in
                try? stream.handle.close()
                try? FileManager.default.removeItem(at: stream.url)
            }
        }
        process.standardOutput = streams[0].handle
        process.standardError = streams[1].handle
        try process.run()
        process.waitUntilExit()
        let texts = try streams.map { String(decoding: try Data(contentsOf: $0.url), as: UTF8.self) }
        return Subprocess(
            status: process.terminationStatus,
            reason: process.terminationReason,
            output: texts[0],
            error: texts[1]
        )
    }

    /// The test process's environment without the variables GitHub Actions
    /// and git read, so a run under test is a dry run and git reads no
    /// configuration of the machine's; then `variables`.
    static func environment(adding variables: [String: String] = [:]) -> [String: String] {
        ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("GITHUB_") && !$0.key.hasPrefix("GIT_") }
            .merging(["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]) { $1 }
            .merging(variables) { $1 }
    }
}

struct SubprocessError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
