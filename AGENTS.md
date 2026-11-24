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

A rule is `Rule.swiftSource(_:in:excluding:reporting:limit:reportingSkipsAs:_:)`,
whose check takes a `SwiftFile` (and, in its other shape, the run's
`Log`) and returns `Finding`s. It reads each changed file through
Steward's `Rule.changedFiles`, so `excluding`, `limit` and
`reportingSkipsAs` mean what they mean there, and keeps the findings
about what the pull request changed, by `SwiftSourceScope`:
`changedDeclarations` (the default, for a rule about one declaration),
`changedTypes` (for order and siblings) or `changedFiles`. The units a
scope judges by are the declarations the model names and the top-level
items (`DeclarationIndex`), and a unit counts as changed by
`changedLineNumbers.overlaps(lineRange) || lineNumbersAfterDeletions.overlaps(lineRange)`.
For each file the rule logs "<rule>: checking <path>" first, so that the
log of a run that dies names the rule and the file; a file with syntax
errors is a skip, through `Finding.skipped`, and the check never sees it.

Rules are syntactic: a type is matched by how it's spelled, not by what
it resolves to, which would take a build. The model of a file is the
package's own value types; raw swift-syntax nodes are an escape hatch, not
the main API. `SwiftFile(source:path:)` parses a file and reads its
`imports` (`Import`), `types` (`TypeDeclaration`), `memberBlocks`
(`MemberBlock`, a type's or an extension's `Member`s in source order, for
ordering rules) and `functions` (`FunctionDeclaration`, with its
`FunctionSignature`, `Parameter`s and `Attribute`s), all at any depth and
in every branch of an `#if`, and `topLevelMembers`, the `Member`s at the
top of the file; names of types are `TypeName`s and access levels
`AccessLevel`s. Every model value has a `location` that goes straight
into a `Finding`'s `at:`, and `file.location(of:)` gives a raw
node one, from `SourceLines`: swift-syntax's `SourceLocationConverter`
follows `#sourceLocation`, whose line a pull request chooses, and can
overflow. `StewardSwift` re-exports `Steward`
(and with it Steward's own re-exports, `GitDiffKit` and
`PullRequestHosting`) and `SwiftSyntax`, so a Dangerfile with Swift rules
imports only `StewardSwift`, even one that reaches for raw nodes;
`ExportsTests` compiles only if it does. A name that two of those modules
declare would be ambiguous there: none does today, and moving either
dependency's bound means checking again. The model follows this
package's version, and a raw node follows swift-syntax's.

A value that holds a node (`SwiftFile`, `FunctionDeclaration`,
`TypeDeclaration`, `MemberBlock`, `Member`) is `Sendable` only: nodes are
`Hashable` by identity, so equality would mean "the same parse", and it
has no memberwise initializer, since its fields would disagree with its
node if set by hand. `signature` is the value to compare. Values that
hold no node (`TypeName`, `AccessLevel`, `Parameter`, `Attribute`,
`FunctionSignature`, `Import`) are `Hashable`, with public memberwise
initializers.

## Dependencies

Two, and nothing else without the maintainer's word:

- **swift-steward**: `Steward` for the library, `StewardTesting` for the
  tests. Core Steward stays language-neutral and takes no third-party
  dependencies, so swift-syntax lives here and never reaches a Dangerfile
  without Swift rules. The requirement is one minor release
  (`.upToNextMinor(from:)`), since a 0.x minor may break the API this
  package builds against: 0.4, whose `Rule.changedFiles`,
  `ChangedFile` (its `changedLineNumbers` and
  `lineNumbersAfterDeletions`) and `Finding.skipped` `Rule.swiftSource`
  builds on.
  A Dangerfile resolves one Steward
  for both packages, so each Steward minor release needs a release of
  this package before such a Dangerfile can move to it.
- **swift-syntax**: `SwiftSyntax` and `SwiftParser`, at a range of
  majors, `"602.0.0"..<"605.0.0"`. SwiftPM picks the newest release in
  the range, and a parser older than the syntax it reads returns error
  nodes, so the upper bound moves soon after each swift-syntax major (one
  for each Swift release, about two a year), in a release of this
  package. The compiler
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
swift test                         # full suite (~25 s); also on Linux
STEWARD_SWIFT_SKIP_NETWORK_TESTS=1 swift test   # offline subset
STEWARD_SWIFT_ORACLE=1 swift test --filter SymbolGraphOracle   # builds the corpus
swift run -c release StewardSwiftBenchmark <directory>          # docs/performance.md
xcodebuild test -scheme steward-lang-swift-Package -destination platform=macOS
swiftlint lint --quiet             # must print nothing
swift test --package-path Dangerfile                # this repository's own PR checks' rules
swift run --package-path Dangerfile Dangerfile --base origin/main   # a dry run of them
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

CI (`.github/workflows/ci.yml`) runs on every pull request, on each push
to `main`, and weekly on `main`, so that a new dependency release that
breaks the package shows between pull requests:
`macos-tests` (the build with warnings as errors, `swift test`,
SwiftLint, and on a pull request this repository's own Dangerfile through
steward-action, then the Dangerfile's tests), `xcode-tests`
(`xcodebuild test`), `linux-tests` (the build
and `swift test` in a `swift:6.2` container) and `lowest-swift-syntax`
(the same, against the range's lower bound). Locally,
`docker run -v "$PWD":/src swift:6.2` runs the Linux checks (copy the tree
out of `/src` first so the two `.build` folders don't mix). GitHub's own
actions are used at their major version tags, such as
`actions/checkout@v7`, which move with each release; an action still at
0.x, where a minor release may break, is pinned to an exact tag or a SHA:
steward-action at `v0.2.0`. CI's token is read-only, but for
`macos-tests`, whose Steward step posts the summary comment
(`pull-requests: write`); the only other token that can write is the
release workflow's (below).

`Dangerfile/` is this repository's own pull request checks: a package of
its own, like a user's, but depending on the checkout it sits in
(`path: ".."`), so every pull request is checked by its own model and
rules, and the root manifest never sees it. Its rules are the build's and
SwiftLint's diagnostics on changed lines (from `build.log` and
`swiftlint.log`, which `macos-tests` writes) and AGENTS.md's conventions
as Swift rules (`Recipes.swift`). Its `Package.resolved` is committed,
since steward-action keys its build cache on that file's hash; move it
with `swift package update --package-path Dangerfile` when the root's
dependencies move. docs/recipes.md shows its rules and docs/model.md the
model; `DocsTests` holds the first to `Dangerfile/Sources` word for word,
between `// Recipe:` markers, and the second's tables, both ways, to the
public properties and cases of each top-level public model type, in its
braces or an extension of it (nested types, such as
`FunctionSignature.Parameter`, are prose only).

## Conventions

swift-steward's
[AGENTS.md](https://github.com/marosoaie/swift-steward/blob/main/AGENTS.md)
sets the coding style and the testing rules here too; read its "Coding
style" and "Testing" sections before writing code. In short: value types
only, functional over imperative, the Swift API Design Guidelines with a
doc comment on every public symbol, strict concurrency and memory safety
with zero warnings, swift-testing with sentence-style names, and oracles
over hand-computed expectations where one exists. Tests pass under both
`swift test` and `xcodebuild test`. A `.timeLimit`'s clock starts before
the body has a thread: it counts the wait to start and, on a test that
suspends, each wait to resume, so a limit has to clear the whole run,
whatever the body does. In a name, "lines" means lines of text: one span
of line numbers is a `lineRange`, a set, list or per-file map of them is
`…LineNumbers` (`changedLineNumbers`, `lineNumbersAfterDeletions`), and
one number stays `line` or `lineNumber`.

The source a rule reads is hostile input: a pull request's author writes
it, and what a rule reports can end up in a public comment. Nothing here
may trap, hang, or read more than the file a rule asked for, whatever the
source holds. Text from the source that goes into a finding passes
through Steward's `Markdown.codeSpan(_:)` or `Markdown.escaped(_:)`.

swift-syntax's parser recovers from broken input, but it isn't safe on
hostile input by itself (measured with 604: SECURITY.md lists the shapes),
so `SwiftFile` defends it:

- `NestingScan` reads the bytes first and refuses a source that nests
  `[`, `<`, `#if` or interpolations past what the parser reads within
  bounded stack, memory and time. It's a heuristic, not a lexer.
- The parse runs on a thread with a 64 MiB stack (`LargeStack`): on
  macOS, `async` code runs on 512 KiB threads. It's no larger, since Linux
  can refuse a far larger reservation.
- `maximumNestingLevel` is 256 in every build configuration (swift-syntax
  defaults to 20 in a debug build, where a Dangerfile usually runs).
- A source that nests past the parser's limit is refused: the parser
  would leave the rest of the file as unexpected text, and declarations
  there would be lost.
- A tree deeper than 512 levels is refused, so a rule's recursive
  `SyntaxVisitor` has the stack to walk it even on a 512 KiB thread in a
  debug build (it dies past about 1,000). Real trees are under 100.
- The parse has a deadline that grows with the source (2 s and 50 µs a
  byte). One that runs out leaves its thread running, and no other parse
  starts until it ends (`ParseGate`). In `Rule.swiftSource` the deadline
  covers the parse, the model and the scopes' index, the package's own
  work on the pull request's input after the nesting scan, one linear
  pass on the rule's own thread before it; the rule's check runs after
  it on the large thread with no limit, as a check in Steward has none
  (`LargeStack.value`, which resumes the rule's task exactly once).
- The package's own walks keep their own stack (`PreorderWalk`), and line
  numbers come from the source's line feeds (`SourceLines`), as git counts
  them; swift-syntax's walks and `SourceLocationConverter` recurse.

A refusal is thrown (`SwiftFile.Refusal`), and must fail the rule that
asked: a skipped file would let a pull request hide from every rule with
one construct. `Rule.swiftSource` makes it a failure whatever the rule's
`reportingSkipsAs`. A source with syntax errors isn't a refusal; it's
read, and `syntax.hasError` says so; `Rule.swiftSource` skips it, a
finding of the rule's skip kind, since its checks would read a damaged
tree. A file that builds can have syntax errors: code for a later
compiler inside an inactive `#if compiler(>=…)`.

The robustness tests read real files whole, cut short and mutated, from a
corpus: this package's own files and swift-argument-parser's, downloaded
once into `~/Library/Caches/steward-lang-swift-tests/` (on Linux,
`${XDG_CACHE_HOME:-~/.cache}/steward-lang-swift-tests/`).
`STEWARD_SWIFT_SKIP_NETWORK_TESTS=1` leaves the download out, and the
tests that need it. The same corpus checks the scopes' index against a
search of every unit, and a finding at each model value's location
against a change to its lines.

README.md's examples are compiled and run: each Swift block is the text
between `// README: <name>` and `// README: end` in
`Tests/ReadmeDangerfile` (the README's Dangerfile and worked rules, an
executable target that isn't a product) or `Tests/StewardSwiftTests/Readme`,
named by the `<!-- README: <name> -->` line before it, and `ReadmeTests`
fails when the two differ, when a block has no example, or when an
example isn't shown. It also runs the Dangerfile and holds the comment the
README shows to what it prints, the scopes' table to what each scope
keeps on the diff shown (which git writes), the quoted skip and refusal
to the rule's, and the manifest to this package's Steward requirement and
to `swift package dump-package`. Change the README and its examples
together. The scopes' diff in the README has context lines that are a
single space: an editor that trims trailing whitespace breaks them, and
`ReadmeTests` says so.

The scope tests take their diffs from git, a base and a head committed in
a temporary repository (`TestRepository`, with Steward's `git diff`
options), and the end-to-end tests run `SwiftRulesFixture`, a Dangerfile
built beside the tests, as its own process, a dry run in such a
repository; one of its rules crashes on a file that asks it to. On a
Mac, each run of that test leaves a crash report, `SwiftRulesFixture-*.ips`,
in `~/Library/Logs/DiagnosticReports`: the system's doing, not the test's.

The oracle is the compiler: `SymbolGraphOracleTests` builds
swift-argument-parser and reads its symbol graph at minimum access level
`private`, and every function it lists at a line of the source (345, each
once: the copies it makes of protocol-extension defaults are left out) must be
read at the same line with the same name and argument labels, `async`,
`throws`, access level and `static`. It doesn't exercise local functions,
which the graph doesn't list, nor access levels that come from an
extension's modifier, which the corpus never relies on: unit tests alone
hold those, and only 9 of its functions are `async`. It also holds the
doc comment of every function, type and member the graph lists (555
have one) to `documentation`, leaving out the initializers the compiler
makes, and compiles `DocumentationShape`'s shapes, the `/** */` forms
the corpus lacks among them, into a package of their own to hold those
too. It needs a build, so it runs only with
`STEWARD_SWIFT_ORACLE=1`; CI's macos-tests job sets it. The benchmark
(`Benchmarks/StewardSwiftBenchmark`, not a product) times the read on a
directory's largest files; [docs/performance.md](docs/performance.md)
records its numbers. Benchmark in a release build only.

## Git

- Commit subjects in imperative mood; bodies explain the why and any
  verification performed.
- `main` is PR-only; the maintainer reviews and merges.
- Never commit large binaries, and no Git LFS: SwiftPM consumers clone
  this repository.
- Material from another project (a fixture, say) is committed with its
  licence next to it and an entry in `THIRD_PARTY_NOTICES.md`, which
  the first such material creates.
- Releases are semver git tags, immutable once published, and 0.x for
  now, so a minor release may break API; users depend on one minor
  release with `.upToNextMinor(from:)`. The maintainer drives version
  numbers and releases; never tag or release unprompted.
- A release is made by the Release workflow
  (`.github/workflows/release.yml`), run by hand from `main` with the
  version, `MAJOR.MINOR.PATCH` without the `v`, and optional notes,
  which GitHub generates when none are given:
  `gh workflow run release.yml --ref main -f version=0.2.0 -F notes=@notes.md`.
  It refuses a version that's already tagged, or isn't greater than
  every version tagged so far, with or without the `v`
  (`.github/scripts/check-release-version.sh`), or that the README's
  manifest doesn't name (the next bullet); runs the tests, with a
  read-only token; and then, in a job of its own that builds nothing
  and alone can write (`contents: write`), tags the commit `vX.Y.Z`, as
  swift-steward's are, publishes the release, and checks that the tag is
  the tested commit. `0.1.0`, the first release, is the one tag without
  the `v`, made by hand before the workflow existed; being immutable, it
  stays, and SwiftPM reads both forms. A published release's tag can't
  be moved, nor deleted while the release exists, and its name can't be
  used again; its title and notes can still be edited.
- Before a release that starts a minor, `MAJOR.MINOR.0`, a pull
  request names it where a consumer reads the current release, and
  merges just before the workflow runs: the README's manifest pins this
  package with `.upToNextMinor(from: "MAJOR.MINOR.0")`, the prose
  before it quotes that and says "at MAJOR.MINOR", and SECURITY.md's
  "Supported versions" says "at MAJOR.MINOR" too (`ReadmeTests` holds
  the prose and SECURITY.md to the manifest). A patch release keeps
  `MAJOR.MINOR.0` and needs none. If the run fails after one merges,
  fix forward or revert it: main doesn't keep naming a release that
  doesn't exist.
