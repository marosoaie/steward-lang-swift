import StewardSwift

// The README's worked rules, each a static property of the Dangerfile, as
// a rule listed in `rules` is.
extension Checks {
    // README: private-last
    /// Private members come last in their type or extension.
    static let privateLast = Rule.swiftSource("Private last", reporting: .changedTypes) { file in
        file.memberBlocks.flatMap { block in
            block.members
                .drop { $0.access.level != .private }
                .filter { $0.access.level != .private }
                .map { .warning("\(Markdown.codeSpan($0.name)) follows a private member.", at: $0.location) }
        }
    }
    // README: end

    // README: final-classes
    /// A class is `final`, unless it's `open`.
    static let finalClasses = Rule.swiftSource("Final classes") { file in
        file.types
            .filter { $0.kind == .class && !$0.isFinal && $0.access.level < .open }
            .map { .warning("Class \(Markdown.codeSpan($0.name)) isn't `final`.", at: $0.location) }
    }
    // README: end

    // README: public-initializers
    /// A public struct has a public initializer, since the memberwise one is
    /// internal.
    static let publicInitializers = Rule.swiftSource("Public initializers") { file in
        file.types
            .filter { $0.kind == .struct && $0.access.level >= .public }
            .filter { type in !type.members.contains { $0.kind == .initializer && $0.access.level >= .public } }
            .map { .warning("Public struct \(Markdown.codeSpan($0.name)) has no public initializer.", at: $0.location) }
    }
    // README: end

    // README: testable-imports
    /// No `@testable import` outside `Tests/`.
    static let testableImports = Rule.swiftSource(
        "Testable imports", excluding: "Tests/**", reporting: .changedFiles
    ) { file in
        file.imports
            .filter { $0.attributes.contains { $0.name == "testable" } }
            .map { .failure("\(Markdown.codeSpan("@testable import \($0.module)")) is for tests.", at: $0.location) }
    }
    // README: end

    // README: flag-parameters
    /// A `Bool` parameter is a flag; two functions, or an enum, read better.
    static let flagParameters = Rule.swiftSource("Flag parameters") { file in
        file.functions.flatMap { function in
            function.parameters
                .filter { $0.type == "Bool" }
                .map { .message("\(Markdown.codeSpan($0.name)) is a `Bool` flag.", at: $0.location) }
        }
    }
    // README: end

    // README: documented-public-api
    /// A public function has a doc comment.
    static let documentedPublicAPI = Rule.swiftSource("Documented public API") { file in
        file.functions
            .filter { $0.access.level >= .public && $0.documentation == nil }
            .map { .warning("Public function \(Markdown.codeSpan($0.name)) has no doc comment.", at: $0.location) }
    }
    // README: end
}
