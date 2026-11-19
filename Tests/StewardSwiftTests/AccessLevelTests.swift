import StewardSwift
import Testing

@Suite("Access levels")
struct AccessLevelTests {
    @Test(
        "a level written out is read as it's written",
        arguments: [
            ("private func f() {}", AccessLevel.Level.private),
            ("fileprivate func f() {}", .fileprivate),
            ("internal func f() {}", .internal),
            ("package func f() {}", .package),
            ("public func f() {}", .public),
            ("class C { open func f() {} }", .open),
            ("@MainActor public static func f() {}", .public),
            ("static public func f() {}", .public),
        ]
    )
    func explicit(source: String, level: AccessLevel.Level) async throws {
        #expect(try await Sample.function(source).access == AccessLevel(level: level, isExplicit: true))
    }

    @Test(
        "a level that isn't written out is the one Swift gives the declaration where it stands",
        arguments: [
            ("func f() {}", AccessLevel.Level.internal),
            ("struct S { func f() {} }", .internal),
            ("private struct S { func f() {} }", .internal),
            ("public struct S { func f() {} }", .internal),
            ("func g() { func f() {} }", .private),
            ("let g = { func f() {} }", .private),
            ("var g: Int { func f() {}; return 0 }", .private),
            ("struct S { init() { func f() {} } }", .private),
            ("protocol P { func f() }", .internal),
            ("public protocol P { func f() }", .public),
            ("private protocol P { func f() }", .fileprivate),
            ("fileprivate protocol P { func f() }", .fileprivate),
            ("public extension S { func f() {} }", .public),
            ("private extension S { func f() {} }", .fileprivate),
            ("package extension S { func f() {} }", .package),
            ("extension S { func f() {} }", .internal),
            ("public struct S { public protocol P { func f() } }", .public),
            ("func g() { struct L { func f() {} } }", .internal),
            ("#if DEBUG\npublic extension S { func f() {} }\n#endif", .public),
        ]
    )
    func implicit(source: String, level: AccessLevel.Level) async throws {
        let function = try await Sample.function(named: "f", in: source)
        #expect(function.access == AccessLevel(level: level, isExplicit: false))
    }

    @Test(
        "a modifier that limits only a setter isn't the declaration's level",
        arguments: ["private(set) func f() {}", "public private(set) func f() {}"]
    )
    func setterModifier(source: String) async throws {
        let access = try await Sample.function(source).access
        #expect(access.isExplicit == source.hasPrefix("public"))
        #expect(access.level == (source.hasPrefix("public") ? .public : .internal))
    }

    @Test("levels are ordered from the most restrictive")
    func ordering() {
        #expect(AccessLevel.Level.allCases.sorted() == [.private, .fileprivate, .internal, .package, .public, .open])
        #expect(AccessLevel.Level.public >= .package)
    }

    @Test("a level describes itself by its keyword, and says when it's implicit")
    func description() {
        #expect(AccessLevel(level: .fileprivate, isExplicit: true).description == "fileprivate")
        #expect(AccessLevel(level: .internal, isExplicit: false).description == "internal (implicit)")
    }
}
