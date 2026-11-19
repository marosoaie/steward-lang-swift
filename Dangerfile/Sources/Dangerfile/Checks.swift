import StewardSwift

/// The rules Steward checks this repository's pull requests with, in the
/// order they run and their findings show: the build's and SwiftLint's
/// diagnostics on the lines a pull request changes, then AGENTS.md's
/// conventions as Swift rules (Recipes.swift, which docs/recipes.md shows).
///
/// ci.yml's macos-tests job runs them through steward-action, which posts
/// the summary as a comment on the pull request; anywhere else,
/// `swift run --package-path Dangerfile` is a dry run that prints it.
@main
struct Checks: Dangerfile {
    static var rules: [Rule] {
        diagnostics
        valueTypes
        documentedPublicAPI
        publicInitializers
        sentenceTestNames
        concatenatedLiterals
    }

    /// The build's and SwiftLint's diagnostics on the lines the pull request
    /// changes, from the logs macos-tests writes before it runs Steward.
    /// Warnings fail too: the build has none, and SwiftLint prints nothing
    /// (AGENTS.md).
    static let diagnostics = Rule.diagnosticsOnChangedLines(
        in: [.xcodebuild("build.log"), .swiftLint("swiftlint.log")],
        failingOn: .warning
    )
}
