import Steward
import SwiftSyntax

/// One of a function's parameters, as the source writes it.
public struct Parameter: Sendable, Hashable {
    /// The argument label callers write, or nil for `_`: `from` in
    /// `load(from url: URL)`, and `url` in `load(url: URL)`.
    public var label: String?

    /// The name inside the function: `url` in both examples above.
    public var name: String

    /// The type as written, such as `URL` or `inout [Int]`, without the
    /// `...` of a variadic parameter.
    public var type: TypeName

    /// Whether the parameter is variadic (`Int...`).
    public var isVariadic: Bool

    /// The default value's spelling, such as `.zero`, or nil when there is
    /// none.
    public var defaultValue: String?

    /// Where the parameter starts: the line of its label, or of its first
    /// attribute or modifier.
    public var location: Location

    /// Creates a parameter.
    public init(
        label: String?,
        name: String,
        type: TypeName,
        isVariadic: Bool,
        defaultValue: String?,
        location: Location
    ) {
        self.label = label
        self.name = name
        self.type = type
        self.isVariadic = isVariadic
        self.defaultValue = defaultValue
        self.location = location
    }
}

extension Parameter {
    init(_ parameter: FunctionParameterSyntax, path: String, lines: SourceLines) {
        let firstName = parameter.firstName.tokenKind == .wildcard ? nil : parameter.firstName.unescapedText
        self.init(
            label: firstName,
            name: parameter.secondName?.unescapedText ?? parameter.firstName.unescapedText,
            type: TypeName(parameter.type),
            isVariadic: parameter.ellipsis != nil,
            defaultValue: parameter.defaultValue.map(\.value.spelling),
            location: Location(path: path, line: lines.line(of: parameter))
        )
    }
}
