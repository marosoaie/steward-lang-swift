import Steward
import SwiftSyntax

/// An `import` declaration.
public struct Import: Sendable, Hashable {
    /// The module, or the declaration in it, as written: `Foundation`, or
    /// `Foundation.Data` for `import struct Foundation.Data`.
    public var module: String

    /// The attributes, such as `@testable` and `@_exported`.
    public var attributes: [Attribute]

    /// The access level the import writes out, such as `internal` in
    /// `internal import Foundation`, or nil when it writes none.
    public var access: AccessLevel.Level?

    /// Whether the import is inside an `#if`.
    public var isConditional: Bool

    /// The line of the `import` keyword.
    public var location: Location

    /// Creates an import.
    public init(
        module: String,
        attributes: [Attribute],
        access: AccessLevel.Level?,
        isConditional: Bool,
        location: Location
    ) {
        self.module = module
        self.attributes = attributes
        self.access = access
        self.isConditional = isConditional
        self.location = location
    }
}

extension Import {
    init(_ declaration: ImportDeclSyntax, path: String, lines: SourceLines) {
        self.init(
            module: declaration.path.spelling,
            attributes: Attribute.all(in: declaration.attributes, path: path, lines: lines),
            access: AccessLevel.Level(writtenIn: declaration.modifiers),
            isConditional: declaration.ancestors.contains { $0.is(IfConfigClauseSyntax.self) },
            location: Location(path: path, line: lines.line(of: declaration.importKeyword))
        )
    }
}
