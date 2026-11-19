import StewardSwift
import StewardTesting
import Testing

@Suite("Function declarations")
struct FunctionDeclarationTests {
    @Test(
        "a function's name is its identifier without backticks, or its operator",
        arguments: [
            ("func load() {}", "load"),
            ("func `default`() {}", "default"),
            ("static func == (lhs: A, rhs: A) -> Bool { true }", "=="),
            ("prefix func √ (x: Double) -> Double { x }", "√"),
            ("func load<T>(_ value: T) {}", "load"),
        ]
    )
    func name(source: String, name: String) async throws {
        #expect(try await Sample.function(source).name == name)
    }

    @Test(
        "async, throws and static are read as written",
        arguments: [
            ("func f() {}", false, false, false),
            ("func f() async {}", true, false, false),
            ("func f() throws {}", false, true, false),
            ("func f() async throws {}", true, true, false),
            ("func f() throws(LoadError) {}", false, true, false),
            ("func f(_ g: () throws -> Void) rethrows {}", false, true, false),
            ("static func f() {}", false, false, true),
            ("class func f() {}", false, false, true),
            ("public static func f() async throws {}", true, true, true),
        ]
    )
    func effects(source: String, isAsync: Bool, isThrowing: Bool, isStatic: Bool) async throws {
        let function = try await Sample.function(source)
        #expect(function.isAsync == isAsync)
        #expect(function.isThrowing == isThrowing)
        #expect(function.isStatic == isStatic)
    }

    @Test(
        "a return type is the type after the arrow, as spelled",
        arguments: [
            ("func f() {}", nil),
            ("func f() -> LoadResult { .empty }", "LoadResult"),
            ("func f() -> [String: Int] { [:] }", "[String: Int]"),
            ("func f() -> Result<Data,any Error> { fatalError() }", "Result<Data, any Error>"),
            ("func f() -> some View { EmptyView() }", "some View"),
            ("func f() -> (Int) -> Void { { _ in } }", "(Int) -> Void"),
            ("func f() -> Void {}", "Void"),
        ] as [(String, TypeName?)]
    )
    func returnType(source: String, returnType: TypeName?) async throws {
        #expect(try await Sample.function(source).returnType == returnType)
    }

    @Test("parameters keep their labels, names, types and default values")
    func parameters() async throws {
        let function = try await Sample.function("""
            func load(
                from url: URL,
                _ data: Data,
                retries: Int = 3,
                options: [Option]... ,
                into buffer: inout [UInt8],
                _: Bool
            ) {}
            """)
        let parameter = { (label: String?, name: String, type: TypeName, variadic: Bool, value: String?, line: Int) in
            Parameter(
                label: label, name: name, type: type, isVariadic: variadic, defaultValue: value,
                location: Location(path: Sample.path, line: line)
            )
        }
        #expect(function.parameters == [
            parameter("from", "url", "URL", false, nil, 2),
            parameter(nil, "data", "Data", false, nil, 3),
            parameter("retries", "retries", "Int", false, "3", 4),
            parameter("options", "options", "[Option]", true, nil, 5),
            parameter("into", "buffer", "inout [UInt8]", false, nil, 6),
            parameter(nil, "_", "Bool", false, nil, 7),
        ])
    }

    @Test("attributes keep their arguments, and those in every branch of an #if count")
    func attributes() async throws {
        let function = try await Sample.function("""
            @MainActor
            @available(*, deprecated, message: "Use load(from:)")
            #if DEBUG
            @inline(never)
            #else
            @inlinable
            #endif
            @discardableResult()
            func load() -> Int { 0 }
            """)
        let location = { Location(path: Sample.path, line: $0) }
        #expect(function.attributes == [
            Attribute(name: "MainActor", arguments: nil, location: location(1)),
            Attribute(
                name: "available", arguments: #"*, deprecated, message: "Use load(from:)""#, location: location(2)
            ),
            Attribute(name: "inline", arguments: "never", location: location(4)),
            Attribute(name: "inlinable", arguments: nil, location: location(6)),
            Attribute(name: "discardableResult", arguments: "", location: location(8)),
        ])
    }

    @Test("the location is the name's line, and the lines run from the first attribute to the closing brace")
    func locationAndLines() async throws {
        let function = try await Sample.function("""
            import Foundation

            /// Loads the thing.
            @MainActor
            public
            func load(
                from url: URL
            ) async throws -> Data {
                Data()
            }

            """)
        #expect(function.location == Location(path: Sample.path, line: 6))
        #expect(function.lines == 4...10)
    }

    @Test("a protocol requirement's lines end with its signature")
    func requirementLines() async throws {
        let function = try await Sample.function("""
            protocol Loader {
                func load(
                    from url: URL
                ) async throws -> Data
                var name: String { get }
            }
            """)
        #expect(function.location.line == 2)
        #expect(function.lines == 2...4)
    }

    @Test("a location goes straight into a finding")
    func locationInFinding() async throws {
        let function = try await Sample.function("func load() -> LoadResult { .empty }")
        let finding = Finding.failure("`load` should be `async`.", at: function.location)
        #expect(finding.location == Location(path: "Sources/App/Sample.swift", line: 1))
    }

    @Test("signatures are equal for functions declared alike, wherever they are and whatever they do")
    func signaturesAlike() async throws {
        let functions = try await Sample.functions(in: """
            func load<T: Decodable>(from url: URL, retries: Int = 3) async throws(LoadError) -> T where T: Sendable {
                try await fetch(url)
            }

            struct Other {
                func load<T: Decodable>(from address: URL, retries: Int = 3) async throws(LoadError) -> T
                    where T: Sendable { fatalError() }
            }
            """)
        #expect(functions.count == 2)
        #expect(functions[0].signature == functions[1].signature)
        #expect(Set(functions.map(\.signature)).count == 1)
        #expect(functions[0].signature.genericParameters == "<T: Decodable>")
        #expect(functions[0].signature.genericRequirements == "where T: Sendable")
        #expect(functions[0].signature.thrownType == "LoadError")
    }

    @Test(
        "signatures differ when what callers see differs",
        arguments: [
            "func load(from url: URL) {}",
            "func load(at url: URL) {}",
            "func load(from url: String) {}",
            "func load(from url: URL) async {}",
            "func load(from url: URL) throws {}",
            "func load(from url: URL) -> Data {}",
            "func load(from url: URL = .root) {}",
            "func load<T>(from url: URL) {}",
            "static func load(from url: URL) {}",
            "public func load(from url: URL) {}",
            "func fetch(from url: URL) {}",
        ]
    )
    func signaturesDiffer(variant: String) async throws {
        let base = try await Sample.function("func load(from url: URL) {}").signature
        let other = try await Sample.function(variant).signature
        #expect((other == base) == (variant == "func load(from url: URL) {}"))
    }

    @Test("the syntax node is the declaration the model was read from")
    func syntaxNode() async throws {
        let function = try await Sample.function("func load(from url: URL) {}")
        #expect(function.syntax.name.text == "load")
        #expect(function.syntax.signature.parameterClause.parameters.count == 1)
    }
}
