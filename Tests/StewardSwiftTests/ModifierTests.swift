import StewardSwift
import Testing

@Suite("Modifiers")
struct ModifierTests {
    @Test("a class's members, functions and the class itself have their modifiers, in order, as spelled")
    func classModifiers() throws {
        let file = try Sample.file("""
            public final class Feed: Base {
                weak var delegate: FeedDelegate?
                private( set ) var items: [Item] = []
                public internal(set) var count = 0
                nonisolated(unsafe) static var shared = Feed()
                lazy var cache = Cache()
                unowned(safe) let owner: Owner
                override init() {}
                required convenience init(other: Feed) { self.init() }
                dynamic func refresh() {}
                class func make() -> Feed { Feed() }
                deinit {}
            }
            """)
        #expect(!file.syntax.hasError)
        #expect(file.types.map(\.modifiers) == [["public", "final"]])
        let members = try #require(file.memberBlocks.first).members
        #expect(members.map { "\($0.name) \($0.modifiers)" } == [
            #"delegate ["weak"]"#, #"items ["private(set)"]"#, #"count ["public", "internal(set)"]"#,
            #"shared ["nonisolated(unsafe)", "static"]"#, #"cache ["lazy"]"#, #"owner ["unowned(safe)"]"#,
            #"init ["override"]"#, #"init ["required", "convenience"]"#, #"refresh ["dynamic"]"#,
            #"make ["class"]"#, "deinit []",
        ])
        #expect(file.functions.map(\.modifiers) == [["dynamic"], ["class"]])
    }

    @Test("structs, enums and protocols have theirs, and a declaration with none has none")
    func otherModifiers() throws {
        let file = try Sample.file("""
            indirect enum Tree {
                indirect case node(Tree, Tree)
                case leaf
            }
            struct Counter {
                var count = 0
                mutating func increment() { count += 1 }
                static prefix func - (counter: Counter) -> Counter { counter }
                func read() -> Int {
                    func local() -> Int { count }
                    return local()
                }
            }
            package protocol Loading {
                static func make() -> Self
            }
            fileprivate struct Hidden {}
            """)
        #expect(!file.syntax.hasError)
        #expect(file.types.map(\.modifiers) == [["indirect"], [], ["package"], ["fileprivate"]])
        #expect(file.memberBlocks.map { $0.members.map(\.modifiers) } == [
            [["indirect"], []], [[], ["mutating"], ["static", "prefix"], []], [["static"]], [],
        ])
        #expect(file.functions.map(\.modifiers) == [["mutating"], ["static", "prefix"], [], [], ["static"]])
    }

    @Test("the names a declaration declares share its modifiers, and the typed views agree with them")
    func sharedNames() throws {
        let members = try #require(try Sample.file("""
            final class Feed {
                weak var a, b: Delegate?
                private(set) static var (c, d) = (1, 2)
            }
            """).memberBlocks.first).members
        #expect(members.map(\.modifiers) == [
            ["weak"], ["weak"], ["private(set)", "static"], ["private(set)", "static"],
        ])
        // `private(set)` limits the setter, not the property.
        #expect(members.map(\.access.level) == [.internal, .internal, .internal, .internal])
        #expect(members.map(\.isStatic) == [false, false, true, true])
    }

    @Test("a rule finds strong delegates and public setters, as issue #15 shows them")
    func issueRecipes() throws {
        let types = try Sample.file("""
            final class FeedModel: ObservableObject {
                weak var delegate: FeedDelegate?
                @Published private(set) var items: [Item] = []
                @Published var isLoading = false
            }
            final class Cache {
                var delegate: CacheDelegate?
            }
            """).types
        let strongDelegates = types.flatMap { type in
            type.members.filter { member in
                member.kind == .property && member.name.hasSuffix("delegate") && !member.modifiers.contains("weak")
            }
        }
        let publicSetters = types.flatMap { type in
            type.members.filter { member in
                member.attributes.contains { $0.name == "Published" } && !member.modifiers.contains("private(set)")
            }
        }
        #expect(strongDelegates.map(\.location.line) == [7])
        #expect(publicSetters.map(\.name) == ["isLoading"])
    }
}
