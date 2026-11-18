import SwiftSyntax

/// A declaration's access level, and whether the source writes it out.
///
/// A level that isn't written out is the one Swift gives the declaration
/// where it stands, read from the source alone:
///
/// - inside a function, closure or accessor body: `private`;
/// - a protocol's requirement: the protocol's level, but at least
///   `fileprivate`;
/// - in an extension with an access modifier: that level (`fileprivate`
///   for `private`);
/// - anywhere else: `internal`.
///
/// What the source alone can't show is left out: a member of an extension
/// without a modifier reads as `internal` even when the extended type is
/// `fileprivate` and so caps it. A `private(set)` or similar modifier
/// limits a setter, not the declaration, so it doesn't count.
public struct AccessLevel: Sendable, Hashable, CustomStringConvertible {
    /// One of Swift's six access levels, ordered from the most restrictive.
    public enum Level: Int, Sendable, Hashable, Comparable, CaseIterable, CustomStringConvertible {
        /// `private`: the enclosing declaration, and its extensions in the
        /// same file.
        case `private`
        /// `fileprivate`: the file.
        case `fileprivate`
        /// `internal`: the module.
        case `internal`
        /// `package`: the package.
        case `package`
        /// `public`: any module.
        case `public`
        /// `open`: any module, which may also subclass or override.
        case `open`

        /// Whether `lhs` is more restrictive than `rhs`.
        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// The keyword, such as `fileprivate`.
        public var description: String {
            switch self {
            case .private: "private"
            case .fileprivate: "fileprivate"
            case .internal: "internal"
            case .package: "package"
            case .public: "public"
            case .open: "open"
            }
        }
    }

    /// The level, written out or not.
    public var level: Level

    /// Whether the declaration's modifiers write the level out.
    public var isExplicit: Bool

    /// Creates an access level.
    public init(level: Level, isExplicit: Bool) {
        self.level = level
        self.isExplicit = isExplicit
    }

    /// The keyword, followed by "(implicit)" when it isn't written out.
    public var description: String {
        isExplicit ? level.description : "\(level) (implicit)"
    }
}

extension AccessLevel {
    /// The access level of `declaration`, whose modifiers are `modifiers`.
    init(of declaration: some SyntaxProtocol, modifiers: DeclModifierListSyntax) {
        if let written = Level(writtenIn: modifiers) {
            self.init(level: written, isExplicit: true)
        } else {
            self.init(level: Level(defaultFor: Syntax(declaration)), isExplicit: false)
        }
    }
}

extension AccessLevel {
    /// The level of a member that can't write one out, an enum's case or a
    /// deinitializer, in `block`: its type's, but at least `internal`, as
    /// Swift gives them (checked with `swiftc -dump-ast`: a case of a
    /// `private` enum is `internal`, a deinit of an `open` class `open`).
    init(implicitMemberOf block: MemberBlockSyntax) {
        let owner = block.parent.flatMap { parent in
            parent.asProtocol((any DeclGroupSyntax).self).map { AccessLevel(of: parent, modifiers: $0.modifiers) }
        }
        self.init(level: Swift.max(.internal, owner?.level ?? .internal), isExplicit: false)
    }
}

extension AccessLevel.Level {
    /// The level a modifier in `modifiers` writes out, if one does.
    init?(writtenIn modifiers: DeclModifierListSyntax) {
        guard let level = modifiers.lazy
            .filter({ $0.detail == nil })
            .compactMap({ AccessLevel.Level(keyword: $0.name.tokenKind) })
            .first
        else { return nil }
        self = level
    }

    init?(keyword: TokenKind) {
        switch keyword {
        case .keyword(.private): self = .private
        case .keyword(.fileprivate): self = .fileprivate
        case .keyword(.internal): self = .internal
        case .keyword(.package): self = .package
        case .keyword(.public): self = .public
        case .keyword(.open): self = .open
        default: return nil
        }
    }

    /// The level Swift gives `declaration` when it writes none, from the
    /// nearest enclosing body or member block.
    init(defaultFor declaration: Syntax) {
        let context = declaration.ancestors.first { ancestor in
            ancestor.is(CodeBlockSyntax.self)
                || ancestor.is(ClosureExprSyntax.self)
                || ancestor.is(AccessorBlockSyntax.self)
                || ancestor.is(MemberBlockSyntax.self)
        }
        guard let context, let block = context.as(MemberBlockSyntax.self) else {
            // At the top of the file, or local: a body or closure.
            self = context == nil ? .internal : .private
            return
        }
        if let owner = block.parent?.as(ProtocolDeclSyntax.self) {
            self = Swift.max(.fileprivate, AccessLevel(of: owner, modifiers: owner.modifiers).level)
        } else if let owner = block.parent?.as(ExtensionDeclSyntax.self),
                  let written = AccessLevel.Level(writtenIn: owner.modifiers) {
            self = Swift.max(.fileprivate, written)
        } else {
            self = .internal
        }
    }
}
