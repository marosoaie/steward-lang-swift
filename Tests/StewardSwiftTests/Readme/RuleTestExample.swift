@testable import ReadmeDangerfile
import StewardSwift
import StewardTesting
import Testing

/// The README's "Testing a rule", as a Dangerfile's own test target has it:
/// there the import is `@testable import Dangerfile`.
@Suite("The README: testing a rule")
struct RuleTestExample {
    // README: rule-test
    @Test("a loader that isn't async is a failure, at its declaration")
    func asyncLoaders() async throws {
        let context = try Context.fixture(
            diff: """
                diff --git a/Sources/Feed/FeedLoader.swift b/Sources/Feed/FeedLoader.swift
                new file mode 100644
                index 0000000..1111111
                --- /dev/null
                +++ b/Sources/Feed/FeedLoader.swift
                @@ -0,0 +1,3 @@
                +struct FeedLoader {
                +    func load() -> LoadResult { .empty }
                +}
                """,
            files: [
                "Sources/Feed/FeedLoader.swift": "struct FeedLoader {\n    func load() -> LoadResult { .empty }\n}\n",
            ]
        )
        #expect(try await Checks.asyncLoaders.evaluate(context) == [
            .failure("`load` returns `LoadResult`, so it's `async`.",
                     at: Location(path: "Sources/Feed/FeedLoader.swift", line: 2)),
        ])
    }
    // README: end
}
