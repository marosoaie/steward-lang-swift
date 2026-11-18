import StewardSwift
import StewardTesting
import Testing

/// Which findings each scope keeps, on pull requests whose diffs git
/// writes from a base and a head.
@Suite("Scopes")
struct SwiftSourceScopeTests {
    @Test("a finding in a function whose body changed is kept, and one in a function left alone isn't")
    func body() async throws {
        let base = """
            func a() {
                print(1)
            }

            func b() {
                print(2)
            }

            """
        let head = base.replacing("print(1)", with: "print(3)")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head) == ["a"])
        // At the top of the file the container is the file.
        #expect(try await Self.kept(.changedTypes, from: base, to: head) == ["a", "b"])
        #expect(try await Self.kept(.changedFiles, from: base, to: head) == ["a", "b"])
    }

    @Test("a rule about the order of members needs changedTypes: the member a new one misplaces didn't change")
    func orderingTrap() async throws {
        let base = """
            struct S {
                func a() {}

                func b() {}
            }

            """
        let head = base.replacing("    func b() {}", with: "    private func p() {}\n\n    func b() {}")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: Self.privateLast).isEmpty)
        #expect(try await Self.kept(.changedTypes, from: base, to: head, by: Self.privateLast)
            == ["b follows a private member"])
    }

    @Test("changedTypes judges a finding by the type or extension whose braces hold it")
    func types() async throws {
        let base = """
            struct Outer {
                func o() {}

                struct Inner {
                    func i() {}
                }
            }

            extension Outer {
                func e() {}

                func f() {}
            }

            func top() {}

            func other() {}

            """
        let head = base
            .replacing("    func o() {}", with: "    func o() { print(1) }")
            .replacing("    func f() {}", with: "    func f() { print(2) }")
            .replacing("func top() {}", with: "func top() { print(3) }")
        // Inner didn't change, though Outer around it did.
        #expect(try await Self.kept(.changedTypes, from: base, to: head) == ["o", "e", "f", "top", "other"])
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head) == ["o", "f", "top"])
    }

    @Test("under changedTypes a nested type's own line belongs to the type around it, whose braces hold it")
    func nestedTypeHeader() async throws {
        let base = """
            struct Outer {
                func o() {}

                struct Inner {
                    func i() {}
                }
            }

            """
        let head = base.replacing("    func o() {}", with: "    func o() { print(1) }")
        #expect(try await Self.kept(.changedTypes, from: base, to: head, by: Self.everyType) == ["Outer", "Inner"])
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: Self.everyType) == ["Outer"])
    }

    @Test("a deletion directly above a unit marks it, whatever was deleted: the known false positive")
    func deletionAbove() async throws {
        let base = """
            func a() {}
            func b() {}
            func c() {}

            """
        // b's deletion follows a and is directly above c: only c is marked.
        let head = base.replacing("func b() {}\n", with: "")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head) == ["c"])
    }

    @Test("a deletion inside a function's body marks the function, and one at the file's end marks nothing")
    func deletionInside() async throws {
        let base = """
            func a() {
                print(1)
                print(2)
            }

            func b() {}
            func c() {}

            """
        let head = base.replacing("    print(2)\n", with: "")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head) == ["a"])
        let atEnd = base.replacing("func c() {}\n", with: "")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: atEnd).isEmpty)
    }

    @Test("a change to the comment lines directly above a declaration marks it, and to one a blank line away doesn't")
    func comments() async throws {
        let base = """
            /// Does a.
            func a() {}

            /// Does b.
            func b() {}

            // Before c.
            /* Also before c. */ func c() {}

            // MARK: - D

            func d() {}

            """
        let head = base
            .replacing("/// Does b.", with: "/// Does b, now.")
            .replacing("// Before c.", with: "// C.")
            .replacing("// MARK: - D", with: "// MARK: - Dee")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head) == ["b", "c"])
    }

    @Test("a function inside #if is a unit of its own, and under changedTypes its type's braces still hold it")
    func conditionalCompilation() async throws {
        let base = """
            struct S {
                #if DEBUG
                func a() {}
                #endif

                func b() {}
            }

            """
        let head = base.replacing("    func a() {}", with: "    func a() { print(1) }")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head) == ["a"])
        #expect(try await Self.kept(.changedTypes, from: base, to: head) == ["a", "b"])
        // The directive's line is a line of the type around it.
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: Self.lines(2)) == ["1", "2"])
    }

    @Test("a top-level statement is a unit, and a line in no unit stands for itself")
    func topLevel() async throws {
        let base = """
            let x = 1
            print(x)
            print(x)

            // A comment of its own.

            print(x)

            """
        let head = base
            .replacing("print(x)\nprint(x)", with: "print(x)\nprint(x + 1)")
            .replacing("// A comment of its own.", with: "// Another comment.")
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: Self.lines(7)) == ["3", "5"])
        #expect(try await Self.kept(.changedTypes, from: base, to: head, by: Self.lines(7)).count == 7)
    }

    @Test("a local let, a closure and an accessor belong to the unit around them")
    func notUnits() async throws {
        let base = """
            struct S {
                var v: Int {
                    let w = 1
                    return w
                }

                func f() {
                    let x = 1
                    _ = { print(x) }
                }
            }

            """
        let head = base
            .replacing("        let w = 1", with: "        let w = 2")
            .replacing("{ print(x) }", with: "{ print(x + 1) }")
        // Lines 3 and 4 are in v's accessor, line 8 is a local `let` in
        // f's body and line 9 a closure there; lines 3 and 9 change.
        let atInner: @Sendable (SwiftFile) -> [Finding] = { file in
            [4, 8].map { (line: Int) in .message("\(line)", at: Location(path: file.path, line: line)) }
        }
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: atInner) == ["4", "8"])
    }

    @Test("a finding with no line, with no location, or about another file is kept in every scope")
    func elsewhere() async throws {
        let base = """
            func a() {}
            func b() {}

            """
        let head = base.replacing("func a() {}", with: "func a() { print(1) }")
        let elsewhere: @Sendable (SwiftFile) -> [Finding] = { file in
            [
                .message("no place"),
                .message("no line", at: Location(path: file.path)),
                .message("another file", at: Location(path: "Sources/Other.swift", line: 2)),
                .message("unchanged", at: Location(path: file.path, line: 2)),
            ]
        }
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: elsewhere)
            == ["no place", "no line", "another file"])
    }

    @Test("a file renamed without a change keeps findings with no line, and those changedTypes keeps at the top")
    func pureRename() async throws {
        let source = """
            func a() {}

            struct S {
                func b() {}
            }

            """
        let context = try SourceChange.context(
            from: ["Sources/Old.swift": source],
            to: ["Sources/New.swift": source]
        )
        let check: @Sendable (SwiftFile) -> [Finding] = { file in
            Self.everyFunction(file) + [.warning("named for its type", at: Location(path: file.path))]
        }
        let kept = try await SwiftSourceScope.allCases.asyncMap { scope in
            try await Rule.swiftSource("Scoped", reporting: scope, check).evaluate(context).map(\.text)
        }
        #expect(kept == [["named for its type"], ["a", "named for its type"], ["a", "b", "named for its type"]])
    }

    @Test("a finding at a line the file doesn't have is a loose line", arguments: [Int.min, -1, 0, 7, Int.max])
    func missingLine(line: Int) async throws {
        let base = "func a() {}\n"
        let head = "func a() { print(1) }\n"
        let atLine: @Sendable (SwiftFile) -> [Finding] = { file in
            [.message("\(line)", at: Location(path: file.path, line: line))]
        }
        #expect(try await Self.kept(.changedDeclarations, from: base, to: head, by: atLine).isEmpty)
        #expect(try await Self.kept(.changedTypes, from: base, to: head, by: atLine) == ["\(line)"])
    }
}

extension SwiftSourceScopeTests {
    /// A finding at every function, its name.
    static let everyFunction: @Sendable (SwiftFile) -> [Finding] = { file in
        file.functions.map { .message($0.name, at: $0.location) }
    }

    /// A finding at every member after a private one in its type or
    /// extension, as a rule that private members come last reports them.
    static let privateLast: @Sendable (SwiftFile) -> [Finding] = { file in
        file.memberBlocks.flatMap { block in
            block.members.drop { $0.access.level != .private }.filter { $0.access.level != .private }
                .map { .warning("\($0.name) follows a private member", at: $0.location) }
        }
    }

    /// The texts of the findings `check` makes that `scope` keeps, for a
    /// pull request that turns `base` into `head`.
    static func kept(
        _ scope: SwiftSourceScope,
        from base: String,
        to head: String,
        by check: @escaping @Sendable (SwiftFile) -> [Finding] = everyFunction
    ) async throws -> [String] {
        let context = try SourceChange.context(from: base, to: head)
        return try await Rule.swiftSource("Scoped", reporting: scope, check).evaluate(context).map(\.text)
    }

    /// A finding at every type, its name.
    static let everyType: @Sendable (SwiftFile) -> [Finding] = { file in
        file.types.map { .message($0.name, at: $0.location) }
    }

    /// A finding at each of the first `count` lines, its number.
    static func lines(_ count: Int) -> @Sendable (SwiftFile) -> [Finding] {
        { file in (1...count).map { .message("\($0)", at: Location(path: file.path, line: $0)) } }
    }
}

extension Sequence {
    /// `map` with an async transform, in order.
    func asyncMap<Transformed>(_ transform: (Element) async throws -> Transformed) async rethrows -> [Transformed] {
        // An imperative loop: `map` takes no async closure.
        var transformed: [Transformed] = []
        for element in self {
            transformed.append(try await transform(element))
        }
        return transformed
    }
}
