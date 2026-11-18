import StewardSwift
import StewardTesting
import Testing

@Suite("Type declarations")
struct TypeDeclarationTests {
    @Test(
        "each kind of type is read, with its name and kind",
        arguments: [
            ("struct Loader {}", TypeDeclaration.Kind.struct, "Loader"),
            ("final class Loader {}", .class, "Loader"),
            ("enum Loader {}", .enum, "Loader"),
            ("actor Loader {}", .actor, "Loader"),
            ("protocol Loader {}", .protocol, "Loader"),
            ("struct `Type` {}", .struct, "Type"),
        ]
    )
    func kinds(source: String, kind: TypeDeclaration.Kind, name: String) throws {
        let types = try Sample.file(source).types
        #expect(types.map(\.kind) == [kind])
        #expect(types.map(\.name) == [name])
    }

    @Test("types are read at any depth, in source order")
    func anyDepth() throws {
        let types = try Sample.file("""
            struct Outer {
                enum Inner {
                    protocol Deepest {}
                }
            }
            extension Outer {
                final class InExtension {}
            }
            func make() {
                struct Local {}
            }
            #if DEBUG
            actor Debug {}
            #else
            actor Release {}
            #endif
            """).types
        #expect(types.map(\.name) == ["Outer", "Inner", "Deepest", "InExtension", "Local", "Debug", "Release"])
    }

    @Test("a type says whether it's final")
    func isFinal() throws {
        let types = try Sample.file("final class A {}\nclass B {}\npublic final class C {}\nstruct D {}").types
        #expect(types.map(\.isFinal) == [true, false, true, false])
    }

    @Test("inherited types are spelled as written, in order")
    func inheritedTypes() throws {
        let type = try #require(try Sample.file("""
            final class Loader: NSObject, @unchecked Sendable, Codable & Hashable {}
            """).types.first)
        #expect(type.inheritedTypes == ["NSObject", "@unchecked Sendable", "Codable & Hashable"])
    }

    @Test(
        "a type's access level is read like a function's",
        arguments: [
            ("struct S {}", AccessLevel(level: .internal, isExplicit: false)),
            ("public struct S {}", AccessLevel(level: .public, isExplicit: true)),
            ("private enum S {}", AccessLevel(level: .private, isExplicit: true)),
            ("func f() { struct S {} }", AccessLevel(level: .private, isExplicit: false)),
            ("public extension Outer { struct S {} }", AccessLevel(level: .public, isExplicit: false)),
        ]
    )
    func access(source: String, access: AccessLevel) throws {
        let type = try #require(try Sample.file(source).types.first { $0.name == "S" })
        #expect(type.access == access)
    }

    @Test("attributes, location and lines are read as for functions")
    func attributesLocationLines() throws {
        let type = try #require(try Sample.file("""
            import Foundation

            /// A loader.
            @MainActor
            @available(macOS 26, *)
            public final class
                Loader {
                func load() {}
            }
            """).types.first)
        #expect(type.attributes.map(\.name) == ["MainActor", "available"])
        #expect(type.location == Location(path: Sample.path, line: 7))
        #expect(type.lines == 4...9)
        #expect(type.syntax.is(ClassDeclSyntax.self))
    }

    @Test("a type's members are its own block's, not its extensions'")
    func members() throws {
        let file = try Sample.file("""
            struct Loader {
                var url: URL
                func load() {}
            }
            extension Loader {
                func reload() {}
            }
            """)
        #expect(file.types.first?.members.map(\.name) == ["url", "load"])
    }
}
