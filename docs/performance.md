# Performance

How long `SwiftFile(source:path:)` takes to read real Swift source, and
what swift-syntax's parse alone takes for comparison. The benchmark is
`Benchmarks/StewardSwiftBenchmark`, an executable target that isn't a
product, so packages that depend on this one never build it:

```sh
swift run -c release StewardSwiftBenchmark <directory> [largest] [runs]
```

For each of a directory's largest Swift files, it takes the median of
`runs` timings, after one run to warm up:

- **Parse:** swift-syntax's `Parser` alone, with the same nesting limit
  as `SwiftFile`.
- **SwiftFile:** the whole read, which is the nesting scan's two passes,
  the hop to a thread with a 64 MiB stack, the parse, the tree-depth
  check, and the model (functions, types, member blocks and imports).

Then it reads every file in the directory once.

## Measured

Apple M4 (10 cores), macOS 26, Swift 6.4.2 (Xcode 27.2), swift-syntax
604.0.0, at steward-lang-swift `8503275`, on 2026-11-18.

### Release

swift-syntax 604.0.0's `Sources`, generated code included, the ten largest
of its 321 files:

| File | KB | Parse (ms) | SwiftFile (ms) | SwiftFile (MB/s) |
|---|---:|---:|---:|---:|
| `SwiftSyntax/generated/RenamedChildrenCompatibility.swift` | 279 | 7.7 | 20.3 | 13.7 |
| `SwiftSyntax/generated/SyntaxVisitor.swift` | 268 | 6.2 | 23.2 | 11.6 |
| `SwiftSyntax/generated/raw/RawSyntaxValidation.swift` | 238 | 9.4 | 28.3 | 8.4 |
| `SwiftSyntax/generated/syntaxNodes/SyntaxNodesJKLMN.swift` | 222 | 6.0 | 19.0 | 11.7 |
| `SwiftSyntax/generated/syntaxNodes/SyntaxNodesAB.swift` | 213 | 5.6 | 18.1 | 11.8 |
| `SwiftSyntax/generated/SyntaxRewriter.swift` | 196 | 5.4 | 18.9 | 10.4 |
| `SwiftSyntax/generated/syntaxNodes/SyntaxNodesGHI.swift` | 182 | 4.9 | 15.7 | 11.7 |
| `SwiftSyntax/generated/syntaxNodes/SyntaxNodesEF.swift` | 179 | 4.8 | 15.0 | 12.0 |
| `SwiftSyntax/generated/syntaxNodes/SyntaxNodesTUVWXYZ.swift` | 177 | 4.8 | 15.2 | 11.7 |
| `SwiftSyntax/generated/syntaxNodes/SyntaxNodesQRS.swift` | 173 | 4.6 | 14.7 | 11.8 |

All 321 files, 6.6 MB: 0.62 s, read once each (10.7 MB/s), none refused.

swift-argument-parser 1.8.2, the robustness tests' corpus, the five largest
of its 165 files:

| File | KB | Parse (ms) | SwiftFile (ms) | SwiftFile (MB/s) |
|---|---:|---:|---:|---:|
| `Tools/generate-manual/MDoc/MDocMacro.swift` | 47 | 0.7 | 3.0 | 16.0 |
| `Sources/ArgumentParser/Parsable Properties/Option.swift` | 45 | 0.8 | 2.3 | 19.5 |
| `Tests/ArgumentParserUnitTests/HelpGenerationTests.swift` | 43 | 1.3 | 4.2 | 10.3 |
| `Tests/ArgumentParserEndToEndTests/DefaultsEndToEndTests.swift` | 33 | 1.1 | 3.7 | 9.1 |
| `Sources/ArgumentParser/Parsing/ArgumentSet.swift` | 26 | 0.8 | 2.4 | 11.3 |

All 165 files, 1.0 MB: 0.11 s, read once each (9.6 MB/s), none refused.

### Debug

steward-action builds a Dangerfile in a debug build, where swift-syntax is
about 40 to 50 times slower (`swift run StewardSwiftBenchmark … 3 3`):

| File | KB | Parse (ms) | SwiftFile (ms) | SwiftFile (MB/s) |
|---|---:|---:|---:|---:|
| `SwiftSyntax/generated/RenamedChildrenCompatibility.swift` | 279 | 479.6 | 942.4 | 0.3 |
| `SwiftSyntax/generated/SyntaxVisitor.swift` | 268 | 414.2 | 921.2 | 0.3 |
| `SwiftSyntax/generated/raw/RawSyntaxValidation.swift` | 238 | 525.5 | 1178.8 | 0.2 |
| `Tools/generate-manual/MDoc/MDocMacro.swift` (swift-argument-parser) | 47 | 49.5 | 117.0 | 0.4 |

All 321 swift-syntax files: 31.8 s. All 165 swift-argument-parser files:
3.8 s.

## What the numbers mean

- **A pull request's files.** A pull request that changes a few files of
  ordinary size costs milliseconds in a release build and a fraction of a
  second each in a debug one. Each rule parses the files it reads itself,
  so the cost adds up with the number of rules that read the same files.
  A cache shared by rules would need shared state; these numbers don't
  call for one yet.
- **The deadline.** `SwiftFile` gives a parse 2 s and 50 µs a byte. Debug
  builds read real code at 2 to 5 µs a byte (the slowest file above takes
  1.2 s, against its 13.9 s), so the margin is about ten times in a debug
  build on this machine, less on a slower CI runner, and several hundred
  times in a release build.
- **The overhead.** `SwiftFile` takes about three times the bare parse: the
  scan reads the bytes twice, the tree is walked to check its depth and
  again to read the model, and the parse hops to a thread of its own.
- **Debug or release.** A Dangerfile built in release reads Swift about 40
  times faster. Whether steward-action should build one in release is a
  question for steward-action and the maintainer, not settled here.
