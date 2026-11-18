import Foundation
import StewardTesting

/// A git repository in a fresh temporary directory, its first branch
/// `main`, with git's global and system configuration shut out and a
/// fixed author. Call `remove()` when done.
struct TestRepository {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("steward-lang-swift-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try git(["init", "--quiet", "--initial-branch=main"])
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Runs git in the repository, and returns its output without the final
    /// line break.
    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        let environment = Subprocess.environment(adding: [
            "GIT_AUTHOR_NAME": "Ada Lovelace",
            "GIT_AUTHOR_EMAIL": "ada@example.com",
            "GIT_COMMITTER_NAME": "Ada Lovelace",
            "GIT_COMMITTER_EMAIL": "ada@example.com",
        ])
        let run = try Subprocess.run(
            URL(fileURLWithPath: "/usr/bin/env"), ["git"] + arguments, environment: environment, in: url
        )
        guard run.status == 0 else {
            throw SubprocessError("git \(arguments.joined(separator: " ")) exited with \(run.status): \(run.error)")
        }
        return run.output.hasSuffix("\n") ? String(run.output.dropLast()) : run.output
    }

    /// Makes the working tree hold exactly `files`, by path, and commits it.
    @discardableResult
    func commit(_ files: [String: String], message: String) throws -> String {
        try git(["rm", "-r", "--quiet", "--ignore-unmatch", "--", "."])
        try files.forEach { path, contents in
            let file = url.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: file)
        }
        try git(["add", "--all"])
        try git(["commit", "--quiet", "--allow-empty", "--no-verify", "--message", message])
        return try git(["rev-parse", "HEAD"])
    }

    /// The diff from `base` to `head`, as a run asks git for it.
    func diff(from base: String, to head: String) throws -> String {
        // Steward's options for `git diff` (Git+Commands.swift), less those
        // that only matter for attributes, submodules and binary files.
        let diff = try git([
            "-c", "core.quotePath=true", "-c", "diff.suppressBlankEmpty=false", "diff", "--no-color",
            "--no-ext-diff", "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/", "-M", "--inter-hunk-context=0",
            "--diff-algorithm=myers", "--indent-heuristic", base, head, "--",
        ])
        return diff.isEmpty ? diff : diff + "\n"
    }
}

/// A pull request that turns one set of files into another.
enum SourceChange {
    /// The context of a pull request that turns `base`'s files into
    /// `head`'s, with the diff git writes for it.
    static func context(from base: [String: String], to head: [String: String]) throws -> Context {
        let repository = try TestRepository()
        defer { repository.remove() }
        let baseCommit = try repository.commit(base, message: "Base")
        let headCommit = try repository.commit(head, message: "Head")
        return try Context.fixture(diff: try repository.diff(from: baseCommit, to: headCommit), files: head)
    }

    /// The context of a pull request that turns `base` into `head` at
    /// `Sample.path`.
    static func context(from base: String, to head: String) throws -> Context {
        try context(from: [Sample.path: base], to: [Sample.path: head])
    }
}
