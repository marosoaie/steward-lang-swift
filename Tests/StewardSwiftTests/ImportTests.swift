import StewardSwift
import StewardTesting
import Testing

@Suite("Imports")
struct ImportTests {
    @Test("imports are read with their modules, paths, kinds, attributes, access and lines")
    func imports() async throws {
        let imports = try await Sample.file("""
            import Foundation
            @testable import App
            @_exported public import Steward
            import struct Foundation.Data
            #if canImport(UIKit)
            import UIKit.UIGestureRecognizerSubclass
            #endif
            internal import `Module`
            """).imports
        let location = { Location(path: Sample.path, line: $0) }
        let plain = { (module: String, line: Int) in
            Import(
                module: module, path: module, kind: nil, attributes: [], access: nil, isConditional: false,
                location: location(line)
            )
        }
        #expect(imports == [
            plain("Foundation", 1),
            Import(
                module: "App", path: "App", kind: nil,
                attributes: [Attribute(name: "testable", arguments: nil, location: location(2))],
                access: nil, isConditional: false, location: location(2)
            ),
            Import(
                module: "Steward", path: "Steward", kind: nil,
                attributes: [Attribute(name: "_exported", arguments: nil, location: location(3))],
                access: .public, isConditional: false, location: location(3)
            ),
            Import(
                module: "Foundation", path: "Foundation.Data", kind: "struct", attributes: [], access: nil,
                isConditional: false, location: location(4)
            ),
            Import(
                module: "UIKit", path: "UIKit.UIGestureRecognizerSubclass", kind: nil, attributes: [],
                access: nil, isConditional: true, location: location(6)
            ),
            Import(
                module: "Module", path: "Module", kind: nil, attributes: [], access: .internal,
                isConditional: false, location: location(8)
            ),
        ])
    }

    @Test("a layering rule reads imports, scoped and submodule imports among them")
    func layeringRecipe() async throws {
        let file = try await SwiftFile(
            source: """
                import GitDiffKit
                import BuildLogKit
                import struct GitDiffKit.ChangedFile
                import GitDiffKit.Submodule
                """,
            path: "Sources/BuildLogKit/Parser.swift"
        )
        // BuildLogKit never imports GitDiffKit.
        let forbidden = file.imports.filter { $0.module == "GitDiffKit" && file.path.hasPrefix("Sources/BuildLogKit/") }
        #expect(forbidden.map(\.location.line) == [1, 3, 4])
    }
}
