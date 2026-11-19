# Recipes

This repository's own conventions, the ones [AGENTS.md](../AGENTS.md)
holds every change to, as Swift rules. They're the rules of its own
[`Dangerfile/`](../Dangerfile), which checks every pull request here, so
each recipe below is compiled, tested in `Dangerfile/Tests`, and run on
the pull requests that change it: word for word, as `DocsTests` holds
this page to `Dangerfile/Sources`.

Each is a static property of the Dangerfile, listed in its `rules`, as in
the [README](../README.md#worked-rules), whose worked rules are recipes too.

## Value types only

A class or an actor is an exception, which its doc comment explains. The
rule reads the doc comment from the type's syntax node, and looks only in
`Sources/`, since a test may need a class (`Bundle(for:)` takes one):

<!-- Recipe: value-types -->
```swift
/// Value types only: a class or an actor is an exception, whose doc
/// comment says why, with the words "A class" or "An actor".
static let valueTypes = Rule.swiftSource("Value types", in: "Sources/**/*.swift") { file in
    file.types
        .filter { $0.kind == .class || $0.kind == .actor }
        .filter { type in
            !type.syntax.leadingTrivia.contains { piece in
                switch piece {
                case .docLineComment(let text), .docBlockComment(let text):
                    text.contains("A class") || text.contains("An actor")
                default:
                    false
                }
            }
        }
        .map { type in
            .warning(
                "\(Markdown.codeSpan(type.name)) isn't a value type, and its doc comment doesn't say why.",
                at: type.location
            )
        }
}
```

## Documented public API

Every public type and function carries a doc comment. Whether one is
public can change with the extension around it, so the rule wants
`.changedTypes`, and the helper it uses comes with it:

<!-- Recipe: documented-public-api -->
```swift
/// Every public type and function has a doc comment. Whether one is
/// public can change with the extension around it, so the rule judges
/// by the type or extension that changed.
static let documentedPublicAPI = Rule.swiftSource(
    "Documented public API", in: "Sources/**/*.swift", reporting: .changedTypes
) { file in
    let types = file.types.filter { $0.access.level >= .public && !isDocumented($0.syntax) }
        .map { ($0.name, $0.location) }
    let functions = file.functions.filter { $0.access.level >= .public && !isDocumented($0.syntax) }
        .map { ($0.name, $0.location) }
    return (types + functions).map { name, location in
        .warning("Public \(Markdown.codeSpan(name)) has no doc comment.", at: location)
    }
}

/// Whether `declaration` has a doc comment in the trivia before it.
static func isDocumented(_ declaration: some SyntaxProtocol) -> Bool {
    declaration.leadingTrivia.contains { piece in
        switch piece {
        case .docLineComment, .docBlockComment: true
        default: false
        }
    }
}
```

## Public initializers

A public model type gets a public memberwise initializer, since Swift's
own is internal; one that holds a syntax node gets none, by design. The
rule looks for an initializer in the type's braces and in an extension in
the same file, and names a type that holds a node by its `syntax`
property:

<!-- Recipe: public-initializers -->
```swift
/// A public struct has a public initializer, in its body or in an
/// extension in the same file, unless it holds a syntax node: such a
/// value has no memberwise initializer, since its fields would disagree
/// with its node if set by hand (AGENTS.md).
static let publicInitializers = Rule.swiftSource(
    "Public initializers", in: "Sources/**/*.swift", reporting: .changedTypes
) { file in
    let initialized = Set(file.memberBlocks
        .filter { block in block.members.contains { $0.kind == .initializer && $0.access.level >= .public } }
        .map { block in
            switch block.owner {
            case .type(_, let name): TypeName(name)
            case .extension(let name): name
            }
        })
    return file.types
        .filter { $0.kind == .struct && $0.access.level >= .public && !initialized.contains(TypeName($0.name)) }
        .filter { type in !type.members.contains { $0.name == "syntax" } }
        .map { .warning("Public struct \(Markdown.codeSpan($0.name)) has no public initializer.", at: $0.location) }
}
```

## Tests named by a sentence

swift-testing names a test with a sentence that says what holds:

<!-- Recipe: sentence-test-names -->
```swift
/// A test's name is a sentence in `@Test("…")`: not a bare `@Test`,
/// which names it after its function, nor a single word.
static let sentenceTestNames = Rule.swiftSource("Sentence test names", in: "Tests/**/*.swift") { file in
    file.functions.compactMap { function in
        guard let test = function.attributes.first(where: { $0.name == "Test" }) else { return nil }
        let arguments = test.arguments ?? ""
        let name = arguments.hasPrefix("\"") ? arguments.dropFirst().prefix { $0 != "\"" } : ""
        guard !name.contains(" ") else { return nil }
        return .warning("Test \(Markdown.codeSpan(function.name)) needs a sentence for a name.", at: test.location)
    }
}
```

## Multiline literals

A multiline string literal over literals joined with `+`. This one goes
below the model, to the tokens of the file's syntax tree, and takes each
`+` with a string literal on each side; its line comes from swift-syntax's
`SourceLocationConverter`:

<!-- Recipe: concatenated-literals -->
```swift
/// A multiline string literal over string literals joined with `+`,
/// read from the tokens: a `+` with a string literal on each side. The
/// line comes from swift-syntax's `SourceLocationConverter`, which also
/// counts a lone carriage return as a line break, unlike git.
static let concatenatedLiterals = Rule.swiftSource("Concatenated literals") { file in
    let converter = SourceLocationConverter(fileName: file.path, tree: file.syntax)
    return file.syntax.tokens(viewMode: .sourceAccurate)
        .filter { $0.tokenKind == .binaryOperator("+") && $0.parent?.is(BinaryOperatorExprSyntax.self) == true }
        .filter { plus in
            let sides = [plus.previousToken(viewMode: .sourceAccurate), plus.nextToken(viewMode: .sourceAccurate)]
            return sides.allSatisfy { side in
                // The literal's quote, as an operand beside the operator.
                side?.parent?.as(StringLiteralExprSyntax.self)?.parent?.id == plus.parent?.parent?.id
            }
        }
        .map { plus in
            .message(
                "A multiline string literal reads better than literals joined with `+`.",
                at: Location(path: file.path, line: plus.startLocation(converter: converter).line)
            )
        }
}
```

## How they run

`ci.yml`'s `macos-tests` job builds and tests the package, writing the
build's and SwiftLint's output to `build.log` and `swiftlint.log`, then
runs this Dangerfile through
[steward-action](https://github.com/marosoaie/steward-action), pinned at
`v0.1.1`, on pull requests. Its first rule reports the diagnostics in
those logs that land on the lines the pull request changes, and the rest
are the recipes above. The Dangerfile depends on the checkout it sits in
(`path: ".."`), so each pull request is checked by its own model and
rules, and its `Package.resolved` is committed, since steward-action keys
its build cache on that file's hash.

Locally:

```sh
swift test --package-path Dangerfile                 # the rules' tests
swift run --package-path Dangerfile Dangerfile --base origin/main   # a dry run
```

A dry run prints the comment it would post. Without `build.log` and
`swiftlint.log` beside it, the diagnostics rule reports that it couldn't
read them.
