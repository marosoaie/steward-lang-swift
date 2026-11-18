import Steward
import SwiftSyntax

/// An `import` declaration.
///
/// ```swift
/// // BuildLogKit never imports GitDiffKit, nor a declaration or a
/// // submodule of it.
/// file.imports.filter { $0.module == "GitDiffKit" }
/// ```
public struct Import: Sendable, Hashable {
    /// The module: the first component of the path, always, so `GitDiffKit`
    /// for `import GitDiffKit`, `import struct GitDiffKit.ChangedFile` and
    /// `import GitDiffKit.Submodule` alike.
    public var module: String

    /// The whole path as written: `GitDiffKit.ChangedFile` for
    /// `import struct GitDiffKit.ChangedFile`, `UIKit.UIGestureRecognizerSubclass`
    /// for a submodule.
    public var path: String

    /// The kind of declaration a scoped import names, such as `struct` in
    /// `import struct GitDiffKit.ChangedFile`, or nil for a module or a
    /// submodule: what tells a declaration from a submodule in `path`.
    public var kind: String?

    /// The attributes, such as `@testable` and `@_exported`.
    public var attributes: [Attribute]

    /// The access level the import writes out, such as `internal` in
    /// `internal import Foundation`, or nil when it writes none. The level
    /// an unwritten one has depends on whether the module enables
    /// `InternalImportsByDefault`, which the source doesn't show.
    public var access: AccessLevel.Level?

    /// Whether the import is inside an `#if`.
    public var isConditional: Bool

    /// The line of the `import` keyword.
    public var location: Location

    /// Creates an import.
    public init(
        module: String,
        path: String,
        kind: String?,
        attributes: [Attribute],
        access: AccessLevel.Level?,
        isConditional: Bool,
        location: Location
    ) {
        self.module = module
        self.path = path
        self.kind = kind
        self.attributes = attributes
        self.access = access
        self.isConditional = isConditional
        self.location = location
    }
}

extension Import {
    init(_ declaration: ImportDeclSyntax, path: String, lines: SourceLines) {
        self.init(
            module: declaration.path.first.map { $0.name.unescapedText } ?? "",
            path: declaration.path.spelling,
            kind: declaration.importKindSpecifier?.text,
            attributes: Attribute.all(in: declaration.attributes, path: path, lines: lines),
            access: AccessLevel.Level(writtenIn: declaration.modifiers),
            isConditional: declaration.ancestors.contains { $0.is(IfConfigClauseSyntax.self) },
            location: Location(path: path, line: lines.line(of: declaration.importKeyword))
        )
    }
}
