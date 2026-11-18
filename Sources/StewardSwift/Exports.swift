// Every entry point of this package is Steward's: `Rule.swiftSource`
// extends `Rule`, takes a `PathPattern` and returns `Finding`s, and each
// model value's `location` is a `Location`. So one import serves a
// Dangerfile's Swift rules, and brings Steward's own re-exports with it,
// GitDiffKit and PullRequestHosting.
@_exported import Steward
// A model value's `syntax` is a swift-syntax node, so a Dangerfile that
// reaches for raw nodes needs no import of its own.
@_exported import SwiftSyntax
