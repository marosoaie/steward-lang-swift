import StewardSwift
import StewardTesting
import Testing

@Suite("Swift files")
struct SwiftFileTests {
    @Test("functions are every func declaration at any depth, in source order")
    func functionsAtAnyDepth() throws {
        let functions = try Sample.functions(in: """
            func topLevel() {
                func nested() {
                    func deeper() {}
                }
                let closure = {
                    func inClosure() {}
                }
                struct Local {
                    func inLocalType() {}
                }
            }

            struct S {
                func inStruct() {}
                static func staticInStruct() {}
            }
            final class C { func inClass() {} }
            enum E { func inEnum() {} }
            actor A { func inActor() {} }
            extension S { func inExtension() {} }
            protocol P {
                func requirement()
                static func staticRequirement()
            }
            #if os(macOS)
            func onMacOS() {}
            #elseif os(Linux)
            func onLinux() {}
            #else
            func elsewhere() {}
            #endif
            """)
        #expect(functions.map(\.name) == [
            "topLevel", "nested", "deeper", "inClosure", "inLocalType",
            "inStruct", "staticInStruct", "inClass", "inEnum", "inActor", "inExtension",
            "requirement", "staticRequirement",
            "onMacOS", "onLinux", "elsewhere",
        ])
    }

    @Test("initializers, subscripts, accessors and closures aren't functions")
    func notFunctions() throws {
        let functions = try Sample.functions(in: """
            struct S {
                init() {}
                deinit {}
                subscript(index: Int) -> Int { index }
                var computed: Int { get { 0 } set {} }
                var stored = { (x: Int) in x }
                func real() {}
            }
            """)
        #expect(functions.map(\.name) == ["real"])
    }

    @Test("the path is the one given, and every location names it")
    func path() throws {
        let file = try SwiftFile(source: "func a() {}\nfunc b() {}", path: "Sources/Feature/Loader.swift")
        #expect(file.path == "Sources/Feature/Loader.swift")
        #expect(file.functions.map(\.location.path) == ["Sources/Feature/Loader.swift", "Sources/Feature/Loader.swift"])
    }

    @Test(
        "source that isn't valid Swift still parses, and says so",
        arguments: [
            "func load( {",
            "struct S { func f() -> }",
            "}}}} func g() {}",
            "",
            "\u{FEFF}func bom() {}",
        ]
    )
    func invalidSource(source: String) throws {
        let file = try Sample.file(source)
        #expect(file.syntax.description == source)
    }

    @Test("a function in source that doesn't parse cleanly is still read")
    func damagedSource() throws {
        let file = try Sample.file("""
            func before() {}
            let x = = 1
            func after() async {}
            """)
        #expect(file.syntax.hasError)
        #expect(file.functions.map(\.name) == ["before", "after"])
        #expect(file.functions.map(\.location.line) == [1, 3])
    }

    @Test(
        "lines are counted as git counts them: a line ends at a line feed",
        arguments: [
            ("func a() {}\nfunc b() {}", [1, 2]),
            ("func a() {}\r\nfunc b() {}", [1, 2]),
            ("func a() {}\rfunc b() {}", [1, 1]),
            ("\n\n\nfunc a() {}", [4]),
            ("/* a\n comment */ func a() {}", [2]),
            ("let s = \"\"\"\n\n\"\"\"\nfunc a() {}", [4]),
        ]
    )
    func lineCounting(source: String, lineNumbers: [Int]) throws {
        #expect(try Sample.functions(in: source).map(\.location.line) == lineNumbers)
    }
}
