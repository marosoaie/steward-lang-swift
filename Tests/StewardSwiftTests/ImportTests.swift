import StewardSwift
import StewardTesting
import Testing

@Suite("Imports")
struct ImportTests {
    @Test("imports are read with their modules, attributes, access and lines")
    func imports() throws {
        let imports = try Sample.file("""
            import Foundation
            @testable import App
            @_exported public import Steward
            import struct Foundation.Data
            #if canImport(UIKit)
            import UIKit
            #endif
            internal import `Module`
            """).imports
        let location = { Location(path: Sample.path, line: $0) }
        #expect(imports == [
            Import(module: "Foundation", attributes: [], access: nil, isConditional: false, location: location(1)),
            Import(
                module: "App",
                attributes: [Attribute(name: "testable", arguments: nil, location: location(2))],
                access: nil,
                isConditional: false,
                location: location(2)
            ),
            Import(
                module: "Steward",
                attributes: [Attribute(name: "_exported", arguments: nil, location: location(3))],
                access: .public,
                isConditional: false,
                location: location(3)
            ),
            Import(module: "Foundation.Data", attributes: [], access: nil, isConditional: false, location: location(4)),
            Import(module: "UIKit", attributes: [], access: nil, isConditional: true, location: location(6)),
            Import(module: "Module", attributes: [], access: .internal, isConditional: false, location: location(8)),
        ])
    }

    @Test("a layering rule reads imports")
    func layeringRecipe() throws {
        let file = try SwiftFile(
            source: "import GitDiffKit\nimport BuildLogKit\n",
            path: "Sources/BuildLogKit/Parser.swift"
        )
        // BuildLogKit never imports GitDiffKit.
        let forbidden = file.imports.filter { $0.module == "GitDiffKit" && file.path.hasPrefix("Sources/BuildLogKit/") }
        #expect(forbidden.map(\.location.line) == [1])
    }
}
