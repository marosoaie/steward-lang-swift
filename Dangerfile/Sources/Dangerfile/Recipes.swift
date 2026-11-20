import StewardSwift

// AGENTS.md's conventions as Swift rules. docs/recipes.md shows each, word
// for word between its `Recipe:` marker and `Recipe: end`, and the root
// package's DocsTests holds it to them.
extension Checks {
    // Recipe: value-types
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
    // Recipe: end

    // Recipe: documented-public-api
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
    // Recipe: end

    // Recipe: public-initializers
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
    // Recipe: end

    // Recipe: sentence-test-names
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
    // Recipe: end

    // Recipe: concatenated-literals
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
    // Recipe: end
}
