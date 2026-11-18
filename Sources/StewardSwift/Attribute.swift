import Steward
import SwiftSyntax

/// An attribute on a declaration, such as `@MainActor` or
/// `@available(*, deprecated)`.
public struct Attribute: Sendable, Hashable {
    /// The name without the `@`, such as `MainActor` or `available`.
    public var name: String

    /// What the parentheses hold, such as `*, deprecated`, or nil when the
    /// attribute has none.
    public var arguments: String?

    /// The line of the `@`.
    public var location: Location

    /// Creates an attribute.
    public init(name: String, arguments: String?, location: Location) {
        self.name = name
        self.arguments = arguments
        self.location = location
    }
}

extension Attribute {
    init(_ attribute: AttributeSyntax, path: String, lines: SourceLines) {
        self.init(
            name: attribute.attributeName.spelling,
            arguments: attribute.leftParen == nil ? nil : attribute.arguments?.spelling ?? "",
            location: Location(path: path, line: lines.line(of: attribute))
        )
    }

    /// The attributes in `list`, in source order, with those in every
    /// branch of an `#if` among them.
    static func all(in list: AttributeListSyntax, path: String, lines: SourceLines) -> [Attribute] {
        list.preorder { !$0.is(AttributeSyntax.self) }
            .compactMap { $0.as(AttributeSyntax.self) }
            .map { Attribute($0, path: path, lines: lines) }
    }
}
