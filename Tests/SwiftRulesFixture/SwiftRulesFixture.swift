// One import: StewardSwift re-exports Steward.
import StewardSwift

/// The Dangerfile the end-to-end tests run as its own process, as a
/// workflow runs one: a rule about one declaration, one about the order of
/// members, and one whose check crashes on a file that asks it to.
@main
struct SwiftRulesFixture: Dangerfile {
    /// A file with this in it crashes the "Crash marker" rule's check.
    static let crashMarker = "// steward-swift-fixture: crash"

    static var rules: [Rule] {
        asyncLoaders
        privateLast
        crash
    }

    static let asyncLoaders = Rule.swiftSource("Async loaders") { file in
        file.functions
            .filter { $0.signature.returnType == "LoadResult" && !$0.signature.isAsync }
            .map { function in
                .failure("\(Markdown.codeSpan(function.name)) returns `LoadResult`, so it's `async`.",
                         at: function.location)
            }
    }

    static let privateLast = Rule.swiftSource("Private last", reporting: .changedTypes) { file in
        file.memberBlocks.flatMap { block in
            block.members.drop { $0.access.level != .private }.filter { $0.access.level != .private }
                .map { .warning("\(Markdown.codeSpan($0.name)) follows a private member.", at: $0.location) }
        }
    }

    static let crash = Rule.swiftSource("Crash marker") { file in
        guard !file.syntax.description.contains(crashMarker) else {
            fatalError("the crash marker")
        }
        return []
    }
}
