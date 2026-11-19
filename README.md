# steward-lang-swift

Rules about the structure of Swift source, such as "a function that
returns `LoadResult` is `async`" or "private functions come last in their
type", written in Swift in a [Steward](https://github.com/marosoaie/swift-steward)
Dangerfile and reported on the pull request like any other rule. They read
the files a pull request changes through a model of each file (its
functions, types, members and imports) parsed with
[swift-syntax](https://github.com/swiftlang/swift-syntax), and they keep
what they find about the code the pull request changed.

A Dangerfile with one such rule:

<!-- README: dangerfile -->
```swift
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
```

A pull request adds `func load(from url: URL) -> LoadResult` to
`FeedLoader`, beside an older `func cached() -> LoadResult` it doesn't
touch. A dry run of the Dangerfile on it prints the comment Steward would
post, here without its footer. On GitHub, the location also links to the
line:

<!-- README: comment -->
> **1 failure** on 30641b9
>
> | | Failures |
> |---|---|
> | :no_entry_sign: | `load` returns `LoadResult`, so it's `async`.<br>`Sources/Feed/FeedLoader.swift:4` |
<!-- README: end -->

`cached()` has the same problem, but the pull request didn't change it,
so the rule keeps quiet about it: see [Which findings are
kept](#which-findings-are-kept). The failure also shows on line 4 in Files
changed, and fails the check.

`import StewardSwift` is the only import: it brings `Steward` (and
Steward's `GitDiffKit` and `PullRequestHosting`) and `SwiftSyntax` with
it. Every example in this README is compiled and run by this package's
tests, so they can't drift from the API.

Nothing is released yet; 0.1.0 will be the first release. Until 1.0, a
minor release may change the API, so a Dangerfile depends on one minor
release.

## Setting up

Start from Steward's [quickstart](https://github.com/marosoaie/swift-steward/blob/main/docs/quickstart.md):
a `Dangerfile/` package beside your own, and a workflow that runs it.
Then add this package to `Dangerfile/Package.swift`:

<!-- README: manifest -->
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dangerfile",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/marosoaie/swift-steward.git", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/marosoaie/steward-lang-swift.git", .upToNextMinor(from: "0.1.0")),
    ],
    targets: [
        .executableTarget(
            name: "Dangerfile",
            dependencies: [
                .product(name: "Steward", package: "swift-steward"),
                .product(name: "StewardSwift", package: "steward-lang-swift"),
            ]
        ),
        .testTarget(
            name: "DangerfileTests",
            dependencies: ["Dangerfile", .product(name: "StewardTesting", package: "swift-steward")]
        ),
    ]
)
```

- **Both packages, one minor release each.** A Dangerfile resolves one
  Steward for both, and each release of this package builds against one
  Steward minor release (0.3 for now). Moving to the next Steward minor
  release waits for a release of this package that takes it. Keep
  swift-steward in the manifest even though `StewardSwift` brings
  `Steward`: the tests need `StewardTesting`, and the requirement is where
  that lockstep shows.
- **swift-syntax comes with it,** at a range of majors, `602.0.0` up to
  but not including `605.0.0`. SwiftPM takes the newest in the range,
  which should be the one for your Swift: a parser older than the syntax
  it reads takes newer syntax for errors.
- **It costs build time.** swift-syntax is a large dependency: on an M4,
  a cold build of the template Dangerfile goes from about 16 s to about
  26 s with it, which steward-action's cache saves on later runs. Commit
  `Dangerfile/Package.resolved`, since the cache's key is its hash.
  Reading a file takes 10 to 20 MB/s in a release build, and about 40
  times as long in a debug build, which is how steward-action builds a
  Dangerfile: 0.2 to 0.4 MB/s ([docs/performance.md](docs/performance.md)).
  Each rule reads its files itself.

The workflow, with steward-action pinned to a release and a time limit
on the job:

<!-- README: workflow -->
```yaml
name: Steward

on:
  pull_request:
    types: [opened, synchronize, reopened, edited, ready_for_review]

permissions:
  contents: read
  pull-requests: write

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  steward:
    runs-on: ubuntu-latest
    # A rule's check has no time limit of its own, so this bounds one that
    # a pull request's file makes slow (SECURITY.md).
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7
      - uses: marosoaie/steward-action@v0.1.1
```

## What a rule can read

`Rule.swiftSource` hands its check a `SwiftFile`: the file's `imports`,
`types`, `memberBlocks` and `functions`, each at any depth (nested in
types, local to functions) and in every branch of an `#if`. Each value
has a `location` for a finding's `at:`. Functions, types, member blocks
and members also have their `lines`, and the file, functions, types and
member blocks their swift-syntax node, `syntax`, for what the model
doesn't hold; `file.location(of:)` gives such a node its location, as git
counts lines. A type's name in a signature or an inheritance clause is a
`TypeName`, which matches a string by its spelling, and an access level
an `AccessLevel`.

Each block below is the body of a test in this repository, so what it
expects holds.

### Functions

<!-- README: read-functions -->
```swift
let file = try SwiftFile(source: """
    public struct FeedLoader {
        /// Loads the feed at `url`.
        @discardableResult
        public static func load(from url: URL, retries: Int = 3) async throws(LoadError) -> LoadResult {
            try await fetch(url, retries: retries)
        }
    }
    """, path: "Sources/Feed/FeedLoader.swift")
let load = file.functions[0]
#expect(load.name == "load")
#expect(load.access.level == .public && load.access.isExplicit)
#expect(load.isStatic && load.isAsync && load.isThrowing)
#expect(load.signature.thrownType == "LoadError")
#expect(load.returnType == "LoadResult")
#expect(load.parameters.map(\.label) == ["from", "retries"])
#expect(load.parameters.map(\.type) == ["URL", "Int"])
#expect(load.parameters[1].defaultValue == "3")
#expect(load.attributes.map(\.name) == ["discardableResult"])
#expect(load.location == Location(path: "Sources/Feed/FeedLoader.swift", line: 4))
#expect(load.lines == 3...6)
```

`signature` holds the declaration's parts as values (name, generic
parameters and requirements, parameters, effects, return type, `static`
and access), so two functions compare by what they declare.

### Types

<!-- README: read-types -->
```swift
let file = try SwiftFile(source: """
    @MainActor
    public final class FeedModel: ObservableObject, Sendable {
        enum State { case idle, loading }
    }
    """, path: "Sources/Feed/FeedModel.swift")
let model = file.types[0]
#expect(model.kind == .class && model.isFinal)
#expect(model.inheritedTypes == ["ObservableObject", "Sendable"])
#expect(model.attributes.map(\.name) == ["MainActor"])
#expect(file.types.map(\.name) == ["FeedModel", "State"])
#expect(file.types[1].access.description == "internal (implicit)")
```

### Member blocks and members

A member block is a type's or an extension's braces, with its members in
source order, for rules about order and about what an extension adds.

<!-- README: read-members -->
```swift
let file = try SwiftFile(source: """
    struct Feed {
        static let shared = Feed()
        var items: [Item] = []
        init() {}
        func refresh() {}
    }

    extension Feed: Equatable {
        private func merge(_ other: Feed) {}
    }
    """, path: "Sources/Feed/Feed.swift")
let (feed, extended) = (file.memberBlocks[0], file.memberBlocks[1])
#expect(feed.members.map(\.kind) == [.property, .property, .initializer, .function])
#expect(feed.members.map(\.name) == ["shared", "items", "init", "refresh"])
#expect(feed.members.map(\.isStatic) == [true, false, false, false])
#expect(extended.owner == .extension("Feed"))
#expect(extended.inheritedTypes == ["Equatable"])
#expect(extended.members.map(\.access.level) == [.private])
```

### Members under `#if`

Every branch is read, since which one builds depends on the build:

<!-- README: read-conditional-members -->
```swift
let file = try SwiftFile(source: """
    struct Feed {
        #if DEBUG
        func dump() {}
        #else
        func log() {}
        #endif
        func refresh() {}
    }
    """, path: "Sources/Feed/Feed.swift")
let members = file.memberBlocks[0].members
#expect(members.map(\.name) == ["dump", "log", "refresh"])
#expect(members.map(\.isConditional) == [true, true, false])
```

### Imports

<!-- README: read-imports -->
```swift
let file = try SwiftFile(source: """
    import Foundation
    @testable import FeedKit
    public import struct Models.Item
    #if canImport(UIKit)
    import UIKit
    #endif
    """, path: "Tests/FeedTests/FeedTests.swift")
#expect(file.imports.map(\.module) == ["Foundation", "FeedKit", "Models", "UIKit"])
#expect(file.imports[1].attributes.map(\.name) == ["testable"])
#expect(file.imports[2].access == .public)
#expect(file.imports[2].kind == "struct" && file.imports[2].path == "Models.Item")
#expect(file.imports.map(\.isConditional) == [false, false, false, true])
```

## Worked rules

Each is a static property of the Dangerfile, like `asyncLoaders` above,
and goes in its `rules`. Text from the source goes into a finding through
`Markdown.codeSpan(_:)`, since the pull request's author writes it and
the comment is Markdown.

Private members come last, a rule about order, so it wants
`.changedTypes` (see [Which findings are kept](#which-findings-are-kept)):

<!-- README: private-last -->
```swift
/// Private members come last in their type or extension.
static let privateLast = Rule.swiftSource("Private last", reporting: .changedTypes) { file in
    file.memberBlocks.flatMap { block in
        block.members
            .drop { $0.access.level != .private }
            .filter { $0.access.level != .private }
            .map { .warning("\(Markdown.codeSpan($0.name)) follows a private member.", at: $0.location) }
    }
}
```

A class is `final`:

<!-- README: final-classes -->
```swift
/// A class is `final`, unless it's `open`.
static let finalClasses = Rule.swiftSource("Final classes") { file in
    file.types
        .filter { $0.kind == .class && !$0.isFinal && $0.access.level < .open }
        .map { .warning("Class \(Markdown.codeSpan($0.name)) isn't `final`.", at: $0.location) }
}
```

A public struct has a public initializer. It reads the type's own
members, so an initializer in an extension doesn't count. On the default
scope its finding is kept when anything in the struct changes, a removed
initializer included. What it misses is a struct that the extension
around it makes public, when only the extension's header changes
(`extension Feed` becoming `public extension Feed`). `.changedTypes`
would catch that, at a price: a top-level struct's own line is in no
braces, so it would report every top-level public struct whenever the
file changed:

<!-- README: public-initializers -->
```swift
/// A public struct has a public initializer, since the memberwise one is
/// internal.
static let publicInitializers = Rule.swiftSource("Public initializers") { file in
    file.types
        .filter { $0.kind == .struct && $0.access.level >= .public }
        .filter { type in !type.members.contains { $0.kind == .initializer && $0.access.level >= .public } }
        .map { .warning("Public struct \(Markdown.codeSpan($0.name)) has no public initializer.", at: $0.location) }
}
```

No `@testable import` outside tests, with the tests left out by the
rule's `excluding:` pattern. It's about where the file is, which a rename
changes without changing a line, so it wants `.changedFiles`:

<!-- README: testable-imports -->
```swift
/// No `@testable import` outside `Tests/`.
static let testableImports = Rule.swiftSource(
    "Testable imports", excluding: "Tests/**", reporting: .changedFiles
) { file in
    file.imports
        .filter { $0.attributes.contains { $0.name == "testable" } }
        .map { .failure("\(Markdown.codeSpan("@testable import \($0.module)")) is for tests.", at: $0.location) }
}
```

No `Bool` flags, from a function's parameters:

<!-- README: flag-parameters -->
```swift
/// A `Bool` parameter is a flag; two functions, or an enum, read better.
static let flagParameters = Rule.swiftSource("Flag parameters") { file in
    file.functions.flatMap { function in
        function.parameters
            .filter { $0.type == "Bool" }
            .map { .message("\(Markdown.codeSpan($0.name)) is a `Bool` flag.", at: $0.location) }
    }
}
```

A public function has a doc comment, which the model doesn't hold: the
function's `syntax` does, in the trivia before its first token. Like the
public initializers, it keeps the default scope, with the same gap, and
one more: a requirement of a protocol that becomes public.
`StewardSwift` re-exports SwiftSyntax, so its types need no import:

<!-- README: documented-public-api -->
```swift
/// A public function has a doc comment, read from its syntax node's
/// leading trivia: SwiftSyntax comes with the import.
static let documentedPublicAPI = Rule.swiftSource("Documented public API") { file in
    file.functions
        .filter { $0.access.level >= .public }
        .filter { function in
            !function.syntax.leadingTrivia.contains { piece in
                switch piece {
                case .docLineComment, .docBlockComment: true
                default: false
                }
            }
        }
        .map { .warning("Public function \(Markdown.codeSpan($0.name)) has no doc comment.", at: $0.location) }
}
```

A raw node follows swift-syntax's version, not this package's: a new
swift-syntax major can change it.

## Which findings are kept

A rule checks whole files, but a pull request shouldn't have to fix what
it didn't touch. `reporting:` says which findings stay, by the line each
one is at:

- **`.changedDeclarations`**, the default, keeps a finding when the
  declaration around its line changed. For a rule about one declaration.
- **`.changedTypes`** keeps a finding when the type or extension whose
  braces hold its line changed anywhere. A line in no braces, as a
  top-level type's own line is, is the file's: there it keeps every
  finding whenever the file changed. For a rule about order or siblings.
- **`.changedFiles`** keeps every finding in a file the pull request
  changed. For a rule about the file, such as its imports.

Here is a file:

<!-- README: scopes-file -->
```swift
struct Feed {
    func refresh() {}

    private func reload() {}

    func clear() {}
}

struct Cache {
    private func evict() {}

    func store() {}
}
```

and the pull request that added `reload()` to it:

<!-- README: scopes-diff -->
```diff
diff --git a/Sources/Feed/Feed.swift b/Sources/Feed/Feed.swift
index 74b1995..ea988fe 100644
--- a/Sources/Feed/Feed.swift
+++ b/Sources/Feed/Feed.swift
@@ -1,6 +1,8 @@
 struct Feed {
     func refresh() {}
 
+    private func reload() {}
+
     func clear() {}
 }
 
```

`privateLast` finds `clear` and `store`, each after a private function,
and each scope keeps:

| Scope | Reports |
|---|---|
| `.changedDeclarations` | nothing |
| `.changedTypes` | `clear` |
| `.changedFiles` | `clear`, `store` |

`clear` is misplaced by the new function, but `clear` itself didn't
change, so `.changedDeclarations` drops it: an ordering rule there would
miss what the pull request did. `store` was misplaced before.

A declaration here is one the model names (a type or an extension, a
member, a function at any depth) or a statement at the top of the file; a
line in a function's body belongs to the function, and `#if` doesn't
count. It changed when the pull request added or rewrote one of its
lines, its doc comment and the comment lines directly above it included,
or deleted lines inside it or directly above it. That last part marks a
declaration whatever was deleted above it, the whole function before it
too: only the base's text could tell. A finding with no line, such as one
about the file's name, is kept in every scope.

## Files a rule doesn't check

A rule says what it didn't check, so a pull request can't pass by
hiding a file:

- **A file it skips** is a finding, a warning by default
  (`reportingSkipsAs:` sets the kind), and a line in the run's log:
  a symbolic link, a submodule, a file over the rule's `limit:`, and a
  file with syntax errors, which the rule's check never sees:
  > Rule “Async loaders” skipped `Sources/Feed/Draft.swift`, with syntax errors. A file the rule should never check belongs in its `excluding:` pattern.

  and in the log, `Async loaders: skipped Sources/Feed/Draft.swift, with syntax errors`.
  A file that builds can have syntax errors: code for a later compiler
  inside an inactive `#if compiler(>=…)` block. A Dangerfile that wants
  such skips to fail the check sets `reportingSkipsAs: .failure`.
- **A file it refuses** is a failure, whatever the skip kind: source
  nested deeper than the parser reads safely, or a read that runs out of
  time. A pull request's author writes the source, so the parse is
  guarded, and a refused file would otherwise hide from every rule:
  > Rule “Async loaders” couldn't read `Sources/Feed/Matrix.swift`. Line 1 nests `[` too deeply, or too often, for the Swift parser to read in bounded time. Split the nested arrays into named constants.

Before each file, a rule logs `Async loaders: checking Sources/Feed/FeedLoader.swift`,
so the log of a run that crashes names the rule and the file.
[SECURITY.md](SECURITY.md) has what the guard does and what it can't.

## Testing a rule

A rule is a value, so a test runs it on a pull request built from a diff
with `Context.fixture(diff:files:)`, from `StewardTesting`. In the
Dangerfile's test target, with `import StewardTesting`, `import Testing`
and `@testable import Dangerfile`:

<!-- README: rule-test -->
```swift
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
```

`SwiftFile(source:path:)` reads a source string directly, for a check
written as a function of its own. Steward's
[rule tests guide](https://github.com/marosoaie/swift-steward/blob/main/docs/rule-tests.md)
has the rest.

## Limits

- **Syntax only.** A type is matched by how it's spelled: `[String]` and
  `Array<String>` are different names, and nothing resolves a typealias
  or a conformance. That would take a build.
- **One file at a time.** A rule sees the file it checks, not the
  extension in another file that adds the initializer it looks for.
- **No macro is expanded,** and `#if` isn't evaluated: every branch is
  read.
- **Implicit access levels come from the source alone.** A member of an
  extension without a modifier reads as `internal`, even when the
  extended type is `fileprivate` and so caps it.
- **A check runs synchronously,** on a thread of its own with a large
  stack, after its file is read. Task-local values don't reach it.

## More

- [docs/model.md](docs/model.md): every type and property a rule reads.
- [docs/recipes.md](docs/recipes.md): this repository's own conventions
  as rules, which check its pull requests.
- [AGENTS.md](AGENTS.md): how the package is built and tested.
- [SECURITY.md](SECURITY.md): reading source a pull request controls.
- [docs/performance.md](docs/performance.md): how fast a file is read.
- [LICENSE](LICENSE)
