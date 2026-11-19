import Foundation
import StewardSwift
import Testing

@Suite("Doc comments")
struct DocumentationTests {
    @Test("a function's doc comment is read as the compiler reads it", arguments: DocumentationShape.all)
    func shapes(shape: DocumentationShape) throws {
        let file = try Sample.file(shape.source(naming: "f"))
        #expect(!file.syntax.hasError)
        let function = try #require(file.functions.first { $0.name == "f" })
        #expect(function.documentation == shape.text)
    }

    @Test("types, member blocks and every kind of member have their doc comments")
    func everyKind() throws {
        let file = try Sample.file("""
            /// A type.
            public struct Feed {
                /// A function.
                func function() {}
                /// An initializer.
                init() {}
                /// A subscript.
                subscript(index: Int) -> Int { index }
                /// A property.
                var property = 0
                /// A nested type.
                enum Nested {
                    /// A case.
                    case value
                }
                /// A type alias.
                typealias Alias = Int
                /// A macro.
                #warning("todo")
            }
            /// An extension.
            extension Feed {
                // Not a doc comment.
                func undocumented() {}
            }
            /// A protocol.
            protocol Loading {
                /// An associated type.
                associatedtype Item
            }
            /// A class.
            final class Cache {
                /// A deinitializer.
                deinit {}
            }
            """)
        #expect(file.types.map(\.documentation) == ["A type.", "A nested type.", "A protocol.", "A class."])
        #expect(file.memberBlocks.map(\.documentation) == [
            "A type.", "A nested type.", "An extension.", "A protocol.", "A class.",
        ])
        #expect(file.functions.map(\.documentation) == ["A function.", nil])
        let members = file.memberBlocks.flatMap(\.members)
        #expect(members.map { "\($0.kind) \($0.documentation ?? "none")" } == [
            "function A function.", "initializer An initializer.", "subscript A subscript.",
            "property A property.", "type A nested type.", "typeAlias A type alias.", "macroExpansion A macro.",
            "case A case.", "function none", "associatedType An associated type.",
            "deinitializer A deinitializer.",
        ])
    }

    @Test("the names a declaration declares share its doc comment")
    func sharedNames() throws {
        let file = try Sample.file("""
            struct Feed {
                /// Shared.
                var a, b: Int
                /// Shared too.
                let (c, d) = (1, 2)
            }
            enum State {
                /// Cases.
                case idle, loading
            }
            """)
        #expect(file.memberBlocks.map { $0.members.map(\.documentation) } == [
            ["Shared.", "Shared.", "Shared too.", "Shared too."], ["Cases.", "Cases."],
        ])
    }

    @Test("a doc comment above #warning is the macro's, not the function's after it")
    func macroBetween() throws {
        let members = try #require(try Sample.file("""
            struct Feed {
                /// A
                #warning("todo")
                func load() {}
            }
            """).memberBlocks.first).members
        #expect(members.map(\.documentation) == ["A", nil])
    }

    // The compiler attaches a doc comment that trails code to the next
    // declaration; the model leaves it to the code it trails.
    @Test("a doc comment after code on the line above isn't the next declaration's")
    func trailingComment() throws {
        let file = try Sample.file("""
            struct Feed {
                var count = 0 /// The count.
                func load() {}
            }
            """)
        #expect(file.functions.map(\.documentation) == [nil])
        #expect(file.memberBlocks.first?.members.map(\.documentation) == [nil, nil])
    }

    // The compiler, as of Swift 6.4, reads the first two with their stars
    // and an empty line after each line, and the third with an empty line
    // between A and B: its reading depends on the line ends; the model's
    // doesn't.
    @Test(
        "a block comment with CRLF line ends reads as one with LF ends",
        arguments: [
            ("/**\r\n * A\r\n * B\r\n */", "A\nB"),
            ("/**\r\n A\r\n   B\r\n */", "A\n  B"),
            ("/** A\r\n B */", "A\nB "),
        ]
    )
    func crlfBlockComments(comment: String, text: String) throws {
        let crlf = try Sample.file(comment + "\r\nfunc f() {}")
        let lf = try Sample.file(comment.replacingOccurrences(of: "\r\n", with: "\n") + "\nfunc f() {}")
        #expect(crlf.functions.map(\.documentation) == [text])
        #expect(lf.functions.map(\.documentation) == [text])
    }

    @Test("a rule finds the public functions with no doc comment, as issue #14 shows it")
    func undocumentedRecipe() throws {
        let file = try Sample.file("""
            /// Loads the feed.
            public func load() {}
            public func refresh() {}
            func helper() {}
            """)
        let undocumented = file.functions.filter { function in
            function.access.level >= .public && function.documentation == nil
        }
        #expect(undocumented.map(\.name) == ["refresh"])
    }
}
