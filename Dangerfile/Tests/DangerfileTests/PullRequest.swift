import StewardTesting

/// Pull requests for the rules' tests.
enum PullRequest {
    /// A pull request that creates each of `files`, each source ending
    /// with a line break.
    static func creating(_ files: [String: String]) throws -> Context {
        let diff = files.sorted { $0.key < $1.key }.map { path, source in
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            let range = lines.count == 1 ? "1" : "1,\(lines.count)"
            return """
                diff --git a/\(path) b/\(path)
                new file mode 100644
                index 0000000..1111111
                --- /dev/null
                +++ b/\(path)
                @@ -0,0 +\(range) @@
                \(lines.map { "+\($0)" }.joined(separator: "\n"))
                """
        }
        return try Context.fixture(diff: diff.joined(separator: "\n") + "\n", files: files)
    }
}
