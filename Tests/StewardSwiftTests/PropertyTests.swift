import StewardSwift
import Testing

@Suite("Property details")
struct PropertyTests {
    /// The property details of the first member block's members, by name.
    private static func properties(_ source: String) throws -> [String: Member.Property?] {
        let file = try Sample.file(source)
        #expect(!file.syntax.hasError)
        let members = file.memberBlocks.flatMap(\.members)
        return Dictionary(members.map { ($0.name, $0.property) }, uniquingKeysWith: { first, _ in first })
    }

    @Test("a property is a let or a var, stored or not as written, with its type and value as written")
    func storedAndComputed() throws {
        let properties = try Self.properties("""
            struct Feed {
                let id: UUID
                var count = 0
                var title: String { "Feed" }
                var total: Int { get { count } set { count = newValue } }
                var items: [Item] = [] { didSet { count = items.count } }
                var state = State.idle { willSet {} didSet {} }
                lazy var cache = Cache()
                static let shared: Feed = Feed(id: UUID())
                @Published var isLoading: Bool = false
                var name: String!
            }
            protocol Loading {
                var isLoading: Bool { get set }
            }
            """)
        let property = { (isConstant: Bool, isStored: Bool, type: TypeName?, value: String?) in
            Member.Property(isConstant: isConstant, isStored: isStored, type: type, initialValue: value)
        }
        #expect(properties == [
            "id": property(true, true, "UUID", nil),
            "count": property(false, true, nil, "0"),
            "title": property(false, false, "String", nil),
            "total": property(false, false, "Int", nil),
            "items": property(false, true, "[Item]", "[]"),
            "state": property(false, true, nil, "State.idle"),
            "cache": property(false, true, nil, "Cache()"),
            "shared": property(true, true, "Feed", "Feed(id: UUID())"),
            "isLoading": property(false, true, "Bool", "false"),
            "name": property(false, true, "String!", nil),
        ])
        let requirement = try Sample.file("protocol Loading { var isLoading: Bool { get set } }").memberBlocks
        #expect(requirement.first?.members.first?.property == property(false, false, "Bool", nil))
    }

    @Test("a name with neither a type nor a value has the type of a valueless name after it; a tuple's have neither")
    func severalNames() throws {
        let properties = try Self.properties("""
            struct Feed {
                var a, b: Int
                var c = 1, d: Double
                var e, f: Int, g = 3
                var h, i: Int = 0
                var s, t: Int = 1, u: Int
                var w, (x, y): (Int, Int)
                var z, _: Int
                let (j, k) = (1, 2)
                let (l, m): (Int, Int) = (3, 4)
            }
            """)
        // Swift rejects `h`, `s`, `w` and `z` ("type annotation missing in
        // pattern"): a binding with a value, a tuple or `_` lends its type
        // to none before it.
        #expect(properties.mapValues { $0?.type?.spelling } == [
            "a": "Int", "b": "Int", "c": nil, "d": "Double", "e": "Int", "f": "Int", "g": nil,
            "h": nil, "i": "Int", "s": nil, "t": "Int", "u": "Int", "w": nil, "x": nil, "y": nil, "z": nil,
            "j": nil, "k": nil, "l": nil, "m": nil,
        ])
        #expect(properties.mapValues { $0?.initialValue } == [
            "a": nil, "b": nil, "c": "1", "d": nil, "e": nil, "f": nil, "g": "3",
            "h": nil, "i": "0", "s": nil, "t": "1", "u": nil, "w": nil, "x": nil, "y": nil, "z": nil,
            "j": nil, "k": nil, "l": nil, "m": nil,
        ])
        #expect(properties.values.allSatisfy { $0?.isStored == true })
        #expect(properties.filter { $0.value?.isConstant == true }.keys.sorted() == ["j", "k", "l", "m"])
    }

    @Test("every other kind of member has no property details")
    func otherKinds() throws {
        let members = try #require(try Sample.file("""
            enum Feed {
                case idle
                init() { self = .idle }
                func load() {}
                subscript(index: Int) -> Int { index }
                typealias ID = String
                struct Nested {}
                #warning("todo")
            }
            """).memberBlocks.first).members
        #expect(members.count == 7)
        #expect(members.allSatisfy { $0.property == nil })
    }

    @Test("a rule finds stored vars in a Sendable struct, and implicitly unwrapped optionals, as issue #16 shows")
    func issueRecipes() throws {
        let type = try #require(try Sample.file("""
            struct Settings: Sendable {
                let id: UUID
                var theme = Theme.system
                var title: String { "Settings" }
                var window: Window!
            }
            """).types.first)
        let isSendable = type.inheritedTypes.contains { $0.spelling == "Sendable" }
        let mutable = isSendable
            ? type.members.filter { $0.property?.isStored == true && $0.property?.isConstant == false }
            : []
        let unwrapped = type.members.filter { $0.property?.type?.spelling.hasSuffix("!") == true }
        #expect(mutable.map(\.name) == ["theme", "window"])
        #expect(unwrapped.map(\.name) == ["window"])
    }
}
