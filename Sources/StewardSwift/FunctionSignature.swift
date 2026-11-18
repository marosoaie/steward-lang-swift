import SwiftSyntax

/// What a function's declaration says to its callers, as data: two
/// functions with equal signatures are declared alike, wherever they are
/// and whatever their bodies do.
///
/// It leaves out the parameters' names inside the function, the location
/// and the body, which callers can't see, and the attributes and the
/// modifiers other than `static`, `class` and the access level (such as
/// `mutating`, `nonisolated`, `override` and `final`), which they can:
/// compare those through `FunctionDeclaration` when a rule needs them.
/// Types compare by spelling, as `TypeName` does.
public struct FunctionSignature: Sendable, Hashable {
    /// A parameter as callers see it.
    public struct Parameter: Sendable, Hashable {
        /// The argument label, or nil for `_`.
        public var label: String?
        /// The type, without the `...` of a variadic parameter.
        public var type: TypeName
        /// Whether the parameter is variadic.
        public var isVariadic: Bool
        /// The default value's spelling, or nil when there is none.
        public var defaultValue: String?

        /// Creates a parameter.
        public init(label: String?, type: TypeName, isVariadic: Bool, defaultValue: String?) {
            self.label = label
            self.type = type
            self.isVariadic = isVariadic
            self.defaultValue = defaultValue
        }
    }

    /// The name, or the operator.
    public var name: String
    /// The generic parameter clause's spelling, such as `<T: Hashable>`, or
    /// nil when there is none.
    public var genericParameters: String?
    /// The parameters, in order.
    public var parameters: [Parameter]
    /// Whether the function is `async`.
    public var isAsync: Bool
    /// Whether the function throws, rethrows included.
    public var isThrowing: Bool
    /// The type in `throws(…)`, or nil when the function throws any error or
    /// doesn't throw.
    public var thrownType: TypeName?
    /// The type after `->`, or nil when there is no `->`.
    public var returnType: TypeName?
    /// The `where` clause's spelling, such as `where T: Sendable`, or nil
    /// when there is none.
    public var genericRequirements: String?
    /// Whether the function is `static` or `class`.
    public var isStatic: Bool
    /// The access level, written out or not.
    public var access: AccessLevel

    /// Creates a signature.
    public init(
        name: String,
        genericParameters: String?,
        parameters: [Parameter],
        isAsync: Bool,
        isThrowing: Bool,
        thrownType: TypeName?,
        returnType: TypeName?,
        genericRequirements: String?,
        isStatic: Bool,
        access: AccessLevel
    ) {
        self.name = name
        self.genericParameters = genericParameters
        self.parameters = parameters
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.thrownType = thrownType
        self.returnType = returnType
        self.genericRequirements = genericRequirements
        self.isStatic = isStatic
        self.access = access
    }
}

extension FunctionSignature {
    init(_ function: FunctionDeclSyntax, access: AccessLevel, isStatic: Bool) {
        let effects = function.signature.effectSpecifiers
        self.init(
            name: function.name.unescapedText,
            genericParameters: function.genericParameterClause?.spelling,
            parameters: function.signature.parameterClause.parameters.map { parameter in
                Parameter(
                    label: parameter.firstName.tokenKind == .wildcard ? nil : parameter.firstName.unescapedText,
                    type: TypeName(parameter.type),
                    isVariadic: parameter.ellipsis != nil,
                    defaultValue: parameter.defaultValue.map(\.value.spelling)
                )
            },
            isAsync: effects?.asyncSpecifier != nil,
            isThrowing: effects?.throwsClause != nil,
            thrownType: effects?.throwsClause?.type.map { TypeName($0) },
            returnType: function.signature.returnClause.map { TypeName($0.type) },
            genericRequirements: function.genericWhereClause?.spelling,
            isStatic: isStatic,
            access: access
        )
    }
}
