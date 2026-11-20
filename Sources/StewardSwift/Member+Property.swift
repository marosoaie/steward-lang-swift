import SwiftSyntax

extension Member {
    /// What a property declares besides its name, as written: syntax alone
    /// can't infer a type, nor see what a property wrapper or a macro does
    /// to the storage.
    ///
    /// ```swift
    /// // No stored `var` in a `Sendable` struct.
    /// type.members.filter { $0.property?.isStored == true && $0.property?.isConstant == false }
    /// ```
    public struct Property: Sendable, Hashable {
        /// Whether it's a `let`.
        public var isConstant: Bool

        /// Whether it's stored, as written: it has no accessors, or only
        /// `willSet` and `didSet`. A property wrapper, or a macro such as
        /// `@Observable`, changes the real storage, which the syntax doesn't
        /// show; a computed property isn't stored, nor is a protocol's
        /// requirement, `{ get set }`.
        public var isStored: Bool

        /// The type as written, or nil when it isn't: inferred, as in
        /// `var count = 0`, or the name is in a tuple pattern, as in
        /// `let (a, b) = pair`. A name with neither a type nor a value has
        /// the type of the name after it when that name has no value
        /// either, as Swift gives it: `a` has `Int` in `var a, b: Int`, but
        /// none in `var a, b: Int = 0`, which Swift rejects.
        public var type: TypeName?

        /// The initial value's spelling, or nil when there's none, or when
        /// the name is in a tuple pattern.
        public var initialValue: String?

        /// Creates a property's details.
        public init(isConstant: Bool, isStored: Bool, type: TypeName?, initialValue: String?) {
            self.isConstant = isConstant
            self.isStored = isStored
            self.type = type
            self.initialValue = initialValue
        }
    }
}

extension Member.Property {
    /// The names `variable` declares, each with its details.
    static func all(in variable: VariableDeclSyntax) -> [(pattern: IdentifierPatternSyntax, property: Self)] {
        let isConstant = variable.bindingSpecifier.tokenKind == .keyword(.let)
        let bindings = Array(variable.bindings)
        // From the last binding back: one with neither a type nor a value
        // takes the type of the binding after it, if that one has no value
        // either; one with a value lends its type to none.
        let types = bindings.reversed().reduce(into: (types: [TypeName?](), lent: TypeName?.none)) { state, binding in
            let written = binding.typeAnnotation.map { TypeName($0.type) }
            let type = written ?? (binding.initializer == nil ? state.lent : nil)
            state.types.append(type)
            state.lent = binding.initializer == nil ? type : nil
        }.types
        return zip(bindings, types.reversed()).flatMap { binding, type in
            let isStored = isStored(binding.accessorBlock)
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                let property = Self(
                    isConstant: isConstant,
                    isStored: isStored,
                    type: type,
                    initialValue: binding.initializer?.value.spelling
                )
                return [(identifier, property)]
            }
            let tupled = Self(isConstant: isConstant, isStored: isStored, type: nil, initialValue: nil)
            return binding.pattern.preorder()
                .compactMap { $0.as(IdentifierPatternSyntax.self) }
                .map { ($0, tupled) }
        }
    }

    /// Whether a binding with `block` is stored: it has none, or only
    /// observers.
    private static func isStored(_ block: AccessorBlockSyntax?) -> Bool {
        guard let block else { return true }
        switch block.accessors {
        case .accessors(let accessors):
            return !accessors.isEmpty && accessors.allSatisfy { accessor in
                [.keyword(.willSet), .keyword(.didSet)].contains(accessor.accessorSpecifier.tokenKind)
            }
        case .getter:
            return false
        }
    }
}
