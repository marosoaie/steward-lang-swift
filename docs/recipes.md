# Recipes

This repository's own conventions, the ones [AGENTS.md](../AGENTS.md)
holds every change to, as Swift rules. They're the rules of its own
[`Dangerfile/`](../Dangerfile), which checks every pull request here, so
each recipe below is compiled, tested in `Dangerfile/Tests`, and run on
the pull requests that change it: word for word, as `DocsTests` holds
this page to `Dangerfile/Sources`.

Each is a static property of the Dangerfile, listed in its `rules`, as in
the [README](../README.md#worked-rules), whose worked rules are recipes too.
Their patterns cover the package's own `Sources/` and `Tests/`; the
Dangerfile's files and the benchmark are left out, but for the literal
rule, which reads every Swift file a pull request changes.

## Value types only

A class or an actor is an exception, which its doc comment explains. The
rule reads the type's `documentation`, and looks only in `Sources/`,
since a test may need a class (`Bundle(for:)` takes one):

<!-- Recipe: value-types -->
```swift
/// Value types only: a class or an actor is an exception, whose doc
/// comment says why, with the words "A class" or "An actor".
static let valueTypes = Rule.swiftSource("Value types", in: "Sources/**/*.swift") { file in
    file.types
        .filter { $0.kind == .class || $0.kind == .actor }
        .filter { type in
            let documentation = type.documentation ?? ""
            return !documentation.contains("A class") && !documentation.contains("An actor")
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

Every public type and function carries a doc comment. It keeps the
default scope, so a declaration that the extension around it makes public
is missed when only the extension's header changes, as is a requirement
of a protocol that becomes public; `.changedTypes`
would catch that, but would report every top-level public type whenever
its file changed (the README's [worked rules](../README.md#worked-rules)
weigh the same choice):

<!-- Recipe: documented-public-api -->
```swift
/// Every public type and function has a doc comment. On the default
/// scope, a declaration that the extension around it makes public is
/// missed when only the extension's header changes, as is a
/// requirement of a protocol that becomes public.
static let documentedPublicAPI = Rule.swiftSource("Documented public API", in: "Sources/**/*.swift") { file in
    let types = file.types.filter { $0.access.level >= .public && $0.documentation == nil }
        .map { ($0.name, $0.location) }
    let functions = file.functions.filter { $0.access.level >= .public && $0.documentation == nil }
        .map { ($0.name, $0.location) }
    return (types + functions).map { name, location in
        .warning("Public \(Markdown.codeSpan(name)) has no doc comment.", at: location)
    }
}
```

## Public initializers

A public model type gets a public memberwise initializer, since Swift's
own is internal; one that holds a syntax node gets none, by design. The
rule looks for an initializer in the struct's own braces, so a struct in
one `#if` branch isn't excused by its namesake in another, and in an
extension of it in the same file, matched by the name with the types
around it (`Outer.Inner`); it knows a type that holds a node by its
`syntax` property. It reports on the whole file, `.changedFiles`: a pull request can
take the initializer out of an extension and leave the struct as it was.
Every public struct here has one, so only a pull request that breaks the
rule hears from it:

<!-- Recipe: public-initializers -->
```swift
/// A public struct has a public initializer, in its braces or in an
/// extension of it in the same file, unless it holds a syntax node:
/// such a value has no memberwise initializer, since its fields would
/// disagree with its node if set by hand (AGENTS.md). An initializer
/// in a struct's braces is that struct's, even when `#if` branches
/// declare two of one name; one in an extension matches by the name
/// with the types around it, `Outer.Inner`, so an extension written
/// with the module's name or a generic type's sugar isn't matched. It
/// reports on the whole file: a pull request can remove the initializer
/// from an extension and leave the struct as it was.
static let publicInitializers = Rule.swiftSource(
    "Public initializers", in: "Sources/**/*.swift", reporting: .changedFiles
) { file in
    let hasPublicInitializer = { (members: [Member]) in
        members.contains { $0.kind == .initializer && $0.access.level >= .public }
    }
    let extended = Set(file.memberBlocks
        .filter { block in
            guard case .extension = block.owner else { return false }
            return hasPublicInitializer(block.members)
        }
        .compactMap { $0.syntax.parent.map(qualifiedName(of:)) })
    return file.types
        .filter { $0.kind == .struct && $0.access.level >= .public }
        .filter { type in
            !hasPublicInitializer(type.members) && !extended.contains(qualifiedName(of: type.syntax))
                && !type.members.contains { $0.name == "syntax" }
        }
        .map { .warning("Public struct \(Markdown.codeSpan($0.name)) has no public initializer.", at: $0.location) }
}

/// The name of the type that `declaration` declares or extends, with
/// the types and extensions around it: `Outer.Inner`.
static func qualifiedName(of declaration: some SyntaxProtocol) -> String {
    sequence(first: Syntax(declaration), next: \.parent).compactMap { node -> String? in
        if let extended = node.as(ExtensionDeclSyntax.self) {
            return extended.extendedType.trimmedDescription
        }
        guard node.isProtocol((any DeclGroupSyntax).self) else { return nil }
        return node.asProtocol((any NamedDeclSyntax).self)?.name.text
    }
    .reversed().joined(separator: ".")
}
```

## Tests named by a sentence

swift-testing names a test with a sentence that says what holds. The
rule reads the name from the string literal's syntax, so a raw literal
(`#"…"#`) or a multiline one reads as the text it holds:

<!-- Recipe: sentence-test-names -->
```swift
/// A test's name is a sentence in `@Test("…")`: not a bare `@Test`,
/// which names it after its function, nor a single word. The name is
/// the attribute's first argument, read from its string literal's
/// syntax, so a raw or a multiline literal reads as the text it holds.
static let sentenceTestNames = Rule.swiftSource("Sentence test names", in: "Tests/**/*.swift") { file in
    file.functions.compactMap { function in
        guard let test = function.attributes.first(where: { $0.name == "Test" }),
              !testName(of: function.syntax).contains(" ")
        else { return nil }
        return .warning("Test \(Markdown.codeSpan(function.name)) needs a sentence for a name.", at: test.location)
    }
}

/// The text of the string literal `@Test` names `function` with, or ""
/// when it names none.
static func testName(of function: FunctionDeclSyntax) -> String {
    let test = function.attributes.compactMap { $0.as(AttributeSyntax.self) }
        .first { $0.attributeName.trimmedDescription == "Test" }
    guard case .argumentList(let arguments) = test?.arguments, let first = arguments.first, first.label == nil,
          let literal = first.expression.as(StringLiteralExprSyntax.self)
    else { return "" }
    return literal.segments.compactMap { $0.as(StringSegmentSyntax.self)?.content.text }.joined()
}
```

## Multiline literals

A multiline string literal over literals joined with `+`. This one goes
below the model, to the tokens of the file's syntax tree, and takes each
`+` with a string literal on each side. Its line comes from
`file.location(of:)`, as git counts lines, not from swift-syntax's
`SourceLocationConverter`, whose lines follow `#sourceLocation`: a pull
request's file can name a line there that overflows its arithmetic and
crashes the run:

<!-- Recipe: concatenated-literals -->
```swift
/// A multiline string literal over string literals joined with `+`,
/// read from the tokens: a `+` with a string literal on each side, at
/// the line `file.location(of:)` gives it.
static let concatenatedLiterals = Rule.swiftSource("Concatenated literals") { file in
    file.syntax.tokens(viewMode: .sourceAccurate)
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
                at: file.location(of: plus)
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
