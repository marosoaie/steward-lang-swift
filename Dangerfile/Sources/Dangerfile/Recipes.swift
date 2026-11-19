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
    // Recipe: end

    // Recipe: documented-public-api
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
    // Recipe: end

    // Recipe: public-initializers
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
    // Recipe: end

    // Recipe: sentence-test-names
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
    // Recipe: end

    // Recipe: concatenated-literals
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
    // Recipe: end
}
