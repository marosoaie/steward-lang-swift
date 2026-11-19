// The README's examples of a Dangerfile and its rules, word for word
// between each `README:` marker and `README: end`: ReadmeTests holds the
// README to them, and runs them.

// README: dangerfile
import StewardSwift

@main
struct Checks: Dangerfile {
    static var rules: [Rule] {
        asyncLoaders
    }

    /// A function that returns `LoadResult` is `async`.
    static let asyncLoaders = Rule.swiftSource("Async loaders") { file in
        file.functions
            .filter { $0.returnType == "LoadResult" && !$0.isAsync }
            .map { .failure("\(Markdown.codeSpan($0.name)) returns `LoadResult`, so it's `async`.", at: $0.location) }
    }
}
// README: end
