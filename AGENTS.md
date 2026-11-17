# steward-lang-swift — contributor & agent guide

Conventions for working in this repository. Written for humans and coding
agents alike; nothing here is specific to any particular tool or model.

## What this is

A Swift package for rules about the structure of Swift source, such as
"a function that returns `LoadResult` is `async`" or "private functions
come last in their type": written in Swift inside a
[Steward](https://github.com/marosoaie/swift-steward) Dangerfile, checked
by the compiler, and reported through Steward like any other rule. One
product, `StewardSwift` (`Sources/StewardSwift/`), tested in
`Tests/StewardSwiftTests/`. Other languages may follow in packages of the
same shape, `steward-lang-<language>`.

Rules are syntactic: a type is matched by how it's spelled, not by what
it resolves to, which would take a build. The model of a file (its
functions, types, members and imports) is the package's own value types;
raw swift-syntax nodes are an escape hatch, not the main API. The library
holds only that escape hatch so far: it re-exports `SwiftSyntax`, so a
Dangerfile that reaches for raw nodes imports only `StewardSwift`. The
model follows this package's version, and a raw node follows
swift-syntax's.

## Dependencies

Two, and nothing else without the maintainer's word:

- **swift-steward**: `Steward` for the library, `StewardTesting` for the
  tests. Core Steward stays language-neutral and takes no third-party
  dependencies, so swift-syntax lives here and never reaches a Dangerfile
  without Swift rules. The requirement is one minor release
  (`.upToNextMinor(from:)`), since a 0.x minor may break the API this
  package builds against. It is 0.2 until it moves to 0.3, whose public
  file reads `Rule.swiftSource` needs. A Dangerfile resolves one Steward
  for both packages, so each Steward minor release needs a release of
  this package before such a Dangerfile can move to it.
- **swift-syntax**: `SwiftSyntax` and `SwiftParser`, at a range of
  majors, `"602.0.0"..<"605.0.0"`. SwiftPM picks the newest release in
  the range, and a parser older than the syntax it reads returns error
  nodes, so the upper bound moves soon after each swift-syntax major
  (one a year, with Swift's), in a release of this package. The compiler
  doesn't bound the range: every major in it builds with each compiler
  Steward supports. A wide range helps the rare Dangerfile whose own
  graph pins swift-syntax. CI builds against the newest release in the
  range and, in its `lowest-swift-syntax` job, against the lower bound.

`Package.resolved` isn't committed: a library's resolution binds no one,
and without it every build takes the newest versions in range, as a
user's Dangerfile would.

## Commands

```sh
swift build                        # must complete with zero warnings
swift test                         # full suite; also on Linux
xcodebuild test -scheme steward-lang-swift -destination platform=macOS
swiftlint lint --quiet             # must print nothing
```

The build against the lowest swift-syntax, as CI runs it:

```sh
swift package resolve
swift package resolve swift-syntax --version 602.0.0   # the range's lower bound
swift test
rm Package.resolved                # back to the newest in range
```

SwiftLint's configuration (`.swiftlint.yml`, with a `Tests/.swiftlint.yml`
override) is swift-steward's: it encodes the mechanically checkable parts
of the style, opts in the functional-preference rules, and allows force
unwraps in tests only. Keep the whole tree violation-free; CI fails on any
violation. When a rule fights a deliberate design decision, disable it in
config or inline, always with a comment saying why.

CI (`.github/workflows/ci.yml`) runs on every pull request and on `main`:
`macos-tests` (the build with warnings as errors, `swift test`, and
SwiftLint), `xcode-tests` (`xcodebuild test`), `linux-tests` (the build
and `swift test` in a `swift:6.2` container) and `lowest-swift-syntax`
(the same, against the range's lower bound). Locally,
`docker run -v "$PWD":/src swift:6.2` runs the Linux checks (copy the tree
out of `/src` first so the two `.build` folders don't mix). Actions are
pinned by release tag, and the workflow token is read-only.

## Conventions

swift-steward's
[AGENTS.md](https://github.com/marosoaie/swift-steward/blob/main/AGENTS.md)
sets the coding style and the testing rules here too; read its "Coding
style" and "Testing" sections before writing code. In short: value types
only, functional over imperative, the Swift API Design Guidelines with a
doc comment on every public symbol, strict concurrency and memory safety
with zero warnings, swift-testing with sentence-style names, and oracles
over hand-computed expectations where one exists. Tests pass under both
`swift test` and `xcodebuild test`.

The source a rule reads is hostile input: a pull request's author writes
it, and what a rule reports can end up in a public comment. Nothing here
may trap, hang, or read more than the file a rule asked for, whatever the
source holds. swift-syntax's parser recovers from broken input and caps
nesting (`maximumNestingLevel`); tests hold the package to that. Text from
the source that goes into a finding passes through Steward's
`Markdown.codeSpan(_:)` or `Markdown.escaped(_:)`.

## Git

- Commit subjects in imperative mood; bodies explain the why and any
  verification performed.
- `main` is PR-only; the maintainer reviews and merges.
- Never commit large binaries, and no Git LFS: SwiftPM consumers clone
  this repository.
- Material from another project (a fixture, say) is committed with its
  licence next to it and an entry in `THIRD_PARTY_NOTICES.md`.
- Releases are semver git tags, immutable once published, and 0.x for
  now, so a minor release may break API; users depend on one minor
  release with `.upToNextMinor(from:)`. They are cut by hand with
  `gh release create`, as git-diff-parser's are: a library has no binary
  to package, so there is no release workflow. The maintainer drives
  version numbers and tags releases; never tag unprompted. The tag scheme
  (`0.1.0`, as git-diff-parser's, or `v0.1.0`, as swift-steward's) is the
  maintainer's to choose before the first release.
