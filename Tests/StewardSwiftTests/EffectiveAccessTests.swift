@testable import StewardSwift
import Testing

@Suite("Effective access")
struct EffectiveAccessTests {
    @Test("a public member of an internal type is internal, and so is what's nested in it")
    func cappedByTheType() throws {
        let file = try Sample.file("""
            struct Loader {
                public var a, b: Int
                public func load() {}
                public struct Inner {
                    public func run() {}
                }
            }
            public struct Shown {
                public func shown() {}
                struct Hidden {
                    public func hidden() {}
                }
            }
            """)
        #expect(file.types.map { "\($0.name) \($0.effectiveAccess)" } == [
            "Loader internal", "Inner internal", "Shown public", "Hidden internal",
        ])
        #expect(file.functions.map { "\($0.name) \($0.effectiveAccess)" } == [
            "load internal", "run internal", "shown public", "hidden internal",
        ])
        let members = file.memberBlocks.flatMap(\.members)
        #expect(members.map { "\($0.name) \($0.access.level) \($0.effectiveAccess)" } == [
            "a public internal", "b public internal", "load public internal", "Inner public internal",
            "run public internal", "shown public public", "Hidden internal internal", "hidden public internal",
        ])
    }

    @Test("open under a public class is public, and public under a package type is package")
    func openAndPackage() throws {
        let file = try Sample.file("""
            public class Base {
                open func f() {}
            }
            open class OpenBase {
                open func g() {}
                public class Nested {
                    open func h() {}
                }
            }
            package struct Kit {
                public func k() {}
            }
            """)
        #expect(file.functions.map { "\($0.name) \($0.effectiveAccess)" } == [
            "f public", "g open", "h public", "k package",
        ])
    }

    @Test("an open class nested in a public type stays open, since another module can subclass it")
    func nestedOpenClass() throws {
        // Checked with the compiler: another module can subclass
        // `Namespace.Base` and `Outer.Inner` and override their methods, but
        // can't subclass `Outer` itself, nor `OpenOuter.Sealed`.
        let file = try Sample.file("""
            public struct Namespace {
                open class Base { open func f() {} }
            }
            public class Outer {
                open class Inner { open func g() {} }
                open func h() {}
            }
            open class OpenOuter {
                public class Sealed { open func k() {} }
            }
            package struct Kit {
                open class Hidden {}
            }
            """)
        #expect(file.types.map { "\($0.name) \($0.effectiveAccess)" } == [
            "Namespace public", "Base open", "Outer public", "Inner open", "OpenOuter open", "Sealed public",
            "Kit package", "Hidden package",
        ])
        #expect(file.functions.map { "\($0.name) \($0.effectiveAccess)" } == [
            "f open", "g open", "h public", "k public",
        ])
        let nested = file.memberBlocks.flatMap(\.members).filter { $0.kind == .type }
        #expect(nested.map { "\($0.name) \($0.effectiveAccess)" } == [
            "Base open", "Inner open", "Sealed public", "Hidden package",
        ])
    }

    @Test("a protocol's requirements and an enum's cases have their type's level")
    func requirementsAndCases() throws {
        let file = try Sample.file("""
            enum Namespace {
                public protocol Fetching {
                    func fetch()
                    var limit: Int { get }
                }
            }
            public protocol Showing {
                func show()
            }
            private protocol Hiding {
                func hide()
            }
            private enum State {
                case idle, done
            }
            public enum Choice {
                case one
            }
            private class Box {
                deinit {}
            }
            """)
        let members = file.memberBlocks.flatMap(\.members)
        #expect(members.map { "\($0.name) \($0.access.level) \($0.effectiveAccess)" } == [
            "Fetching public internal", "fetch public internal", "limit public internal", "show public public",
            "hide fileprivate private", "idle internal private", "done internal private", "one public public",
            "deinit internal private",
        ])
    }

    @Test("an extension doesn't cap what it holds, since its type may be declared in another file")
    func extensionsDontCap() throws {
        let file = try Sample.file("""
            struct Hidden {}
            extension Hidden {
                public func f() {}
                public struct Nested {
                    public func g() {}
                }
            }
            internal extension Hidden {
                public var x: Int { 0 }
            }
            private extension Hidden {
                func p() {}
            }
            """)
        let extensions = file.memberBlocks.filter { if case .extension = $0.owner { true } else { false } }
        #expect(extensions.flatMap(\.members).map { "\($0.name) \($0.effectiveAccess)" } == [
            "f public", "Nested public", "x public", "p fileprivate",
        ])
        #expect(file.types.map { "\($0.name) \($0.effectiveAccess)" } == ["Hidden internal", "Nested public"])
        #expect(file.functions.map { "\($0.name) \($0.effectiveAccess)" } == ["f public", "g public", "p fileprivate"])
    }

    @Test("a function, closure or accessor body, or a switch case, caps what's declared in it to private")
    func bodiesCap() throws {
        // A `switch` case's statements are local too, at the top of a
        // `main.swift` among them, though no code block holds them.
        let file = try Sample.file("""
            switch value {
            case 1:
                struct InCase {}
                func inCase() {}
            default:
                break
            }
            public func outer() {
                public struct Local {
                    public func inner() {}
                }
                func nested() {}
                let make = { struct InClosure {} }
            }
            public var computed: Int {
                struct InAccessor {}
                return 0
            }
            """)
        #expect(file.types.map { "\($0.name) \($0.access.level) \($0.effectiveAccess)" } == [
            "InCase internal private", "Local public private", "InClosure private private",
            "InAccessor private private",
        ])
        #expect(file.functions.map { "\($0.name) \($0.effectiveAccess)" } == [
            "inCase private", "outer public", "inner private", "nested private",
        ])
    }

    @Test("a top-level member's effective level is its own")
    func topLevel() throws {
        let members = try Sample.file("""
            public let version = "1.0"
            let hidden = 0
            private typealias Alias = Int
            open class Base {}
            """).topLevelMembers
        #expect(members.map { "\($0.name) \($0.effectiveAccess)" } == [
            "version public", "hidden internal", "Alias private", "Base open",
        ])
        #expect(members.allSatisfy { $0.effectiveAccess == $0.access.level })
    }

    @Test("functions under a hundred nested types get their level about as fast as under one")
    func deepTypes() throws {
        // A gate and a limit of the test's own, as the index's tests have.
        let read = { (depth: Int) throws -> SwiftFile in
            let functions = String(repeating: "public func f() {}\n", count: 5_000)
            let source = String(repeating: "public struct S {\n", count: depth) + functions
                + String(repeating: "}\n", count: depth)
            return try SwiftFile.read(source: source, path: Sample.path, timeLimit: .seconds(300), gate: ParseGate())
        }
        let (shallow, deep) = (try read(1), try read(100))
        #expect(deep.functions.count == 5_000 && deep.functions.allSatisfy { $0.effectiveAccess == .public })
        // The faster of five, each way, taken in turns. A walk to the top
        // for each function would take 100 types' steps for each, not one.
        let levels = { (file: SwiftFile, nodes: [Syntax]) in
            let caps = AccessCaps(tree: file.syntax, nodes: nodes)
            return file.functions.map { caps.effectiveLevel(of: $0.syntax, declared: $0.access.level) }
        }
        let (shallowNodes, deepNodes) = (Array(shallow.syntax.preorder()), Array(deep.syntax.preorder()))
        let clock = ContinuousClock()
        let rounds = (0..<5).map { _ in
            (clock.measure { _ = levels(shallow, shallowNodes) }, clock.measure { _ = levels(deep, deepNodes) })
        }
        let (shallowTime, deepTime) = (rounds.map(\.0).min() ?? .zero, rounds.map(\.1).min() ?? .zero)
        #expect(deepTime < shallowTime * 2 + .milliseconds(100), "\(deepTime) under 100 types, \(shallowTime) under 1")
    }

    @Test("types and functions under ninety-five #if blocks at the top get their levels about as fast as flat ones")
    func deepConditionalCompilation() throws {
        // A gate and a limit of the test's own, as the index's tests have.
        // No level is written, so each declaration's own level is its
        // default, which a walk up to the root would find too.
        let read = { (depth: Int) throws -> SwiftFile in
            let declarations = String(repeating: "struct T {}\nfunc f() {}\n", count: 2_500)
            let source = String(repeating: "#if A\n", count: depth) + declarations
                + String(repeating: "#endif\n", count: depth)
            return try SwiftFile.read(source: source, path: Sample.path, timeLimit: .seconds(300), gate: ParseGate())
        }
        let (flat, deep) = (try read(0), try read(95))
        let levels = deep.types.map(\.effectiveAccess) + deep.functions.map(\.effectiveAccess)
        #expect(levels.count == 5_000 && levels.allSatisfy { $0 == .internal })
        // The faster of five, each way, taken in turns: the caps, with each
        // type's own level, and each function's level and cap. A walk up to
        // the root for any of them would take 95 `#if`s' steps.
        let levelsOf = { (file: SwiftFile, nodes: [Syntax]) in
            let caps = AccessCaps(tree: file.syntax, nodes: nodes)
            return file.functions.map { function in
                let declared = caps.accessLevel(of: function.syntax, modifiers: function.syntax.modifiers)
                return caps.effectiveLevel(of: function.syntax, declared: declared.level)
            }
        }
        let (flatNodes, deepNodes) = (Array(flat.syntax.preorder()), Array(deep.syntax.preorder()))
        let clock = ContinuousClock()
        let rounds = (0..<5).map { _ in
            (clock.measure { _ = levelsOf(flat, flatNodes) }, clock.measure { _ = levelsOf(deep, deepNodes) })
        }
        let (flatTime, deepTime) = (rounds.map(\.0).min() ?? .zero, rounds.map(\.1).min() ?? .zero)
        #expect(deepTime < flatTime * 2 + .milliseconds(100), "\(deepTime) under 95 #if, \(flatTime) under none")
        // And the types, blocks and functions built as SwiftFile builds them,
        // each reading its own level: the faster of three, each way.
        let build = { (file: SwiftFile, nodes: [Syntax]) in
            let (caps, lines) = (AccessCaps(tree: file.syntax, nodes: nodes), file.sourceLines)
            let types = nodes.compactMap { $0.as(DeclSyntax.self) }
                .compactMap { TypeDeclaration($0, path: file.path, lines: lines, caps: caps) }
            let blocks = nodes.compactMap { $0.as(MemberBlockSyntax.self) }
                .compactMap { MemberBlock($0, path: file.path, lines: lines, caps: caps) }
            let functions = nodes.compactMap { $0.as(FunctionDeclSyntax.self) }
                .map { FunctionDeclaration($0, path: file.path, lines: lines, caps: caps) }
            return types.count + blocks.count + functions.count
        }
        let builds = (0..<3).map { _ in
            (clock.measure { _ = build(flat, flatNodes) }, clock.measure { _ = build(deep, deepNodes) })
        }
        let (flatBuild, deepBuild) = (builds.map(\.0).min() ?? .zero, builds.map(\.1).min() ?? .zero)
        #expect(deepBuild < flatBuild * 2 + .milliseconds(100), "\(deepBuild) under 95 #if, \(flatBuild) under none")
    }
}
