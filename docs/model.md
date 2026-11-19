# The model

What `Rule.swiftSource` hands a check: a `SwiftFile`, and the values it
holds. Every value has a `location` for a finding's `at:`. Values that
hold a syntax node are `Sendable` only, and have no memberwise
initializer, since their fields would disagree with their node if set by
hand; the others are `Hashable`, with public memberwise initializers, for
tests. The [README](../README.md#what-a-rule-can-read) has an example of
each, and each declaration's doc comment has the corners.

A raw node (`syntax`) follows swift-syntax's version, not this package's.
`StewardSwift` re-exports `SwiftSyntax`, so its types need no import.

## `SwiftFile`

One file, read and checked: `SwiftFile(source:path:)` reads a source
string, for a test or a check of your own, and throws a `SwiftFile.Refusal`
for one it can't read safely ([SECURITY.md](../SECURITY.md)).

| Property | What it holds |
|---|---|
| `path` | The path in the repository, which every `location` names. |
| `imports` | The `import` declarations, in source order. |
| `types` | Every struct, class, enum, actor and protocol, in source order, at any depth, in every branch of an `#if`. |
| `memberBlocks` | Every type's and extension's members, block by block, in source order, at any depth. |
| `functions` | Every `func`, in source order, at any depth: in types, extensions and protocols, in other functions and closures, in every branch of an `#if`. |
| `syntax` | The file's `SourceFileSyntax`. |

## `FunctionDeclaration`

A `func`. Initializers, subscripts and accessors aren't functions here;
`MemberBlock.members` has them.

| Property | What it holds |
|---|---|
| `name` | The name without its parameters, such as `load`, or an operator. |
| `access` | Its `AccessLevel`, written out or not. |
| `isAsync` | Whether it's `async`. |
| `isThrowing` | Whether it throws: `throws`, `throws(E)` or `rethrows`. |
| `isStatic` | Whether it's `static` or `class`. |
| `returnType` | The `TypeName` after `->`, or nil. |
| `parameters` | Its `Parameter`s, in order. |
| `attributes` | Its `Attribute`s, in order. |
| `location` | The line of its name. |
| `lines` | From its first attribute or modifier to its closing brace. |
| `signature` | Its `FunctionSignature`, what it says to callers, as a value that compares. |
| `syntax` | Its `FunctionDeclSyntax`. |

## `FunctionSignature`

A function's declaration as data: two functions compare by what they
declare.

| Property | What it holds |
|---|---|
| `name` | The name, or the operator. |
| `genericParameters` | The generic parameter clause's spelling, such as `<T: Hashable>`, or nil. |
| `parameters` | Each parameter's label, type, whether it's variadic and its default value, as a `FunctionSignature.Parameter`. |
| `isAsync` | Whether it's `async`. |
| `isThrowing` | Whether it throws. |
| `thrownType` | The type in `throws(…)`, or nil. |
| `returnType` | The type after `->`, or nil. |
| `genericRequirements` | The `where` clause's spelling, or nil. |
| `isStatic` | Whether it's `static` or `class`. |
| `access` | Its `AccessLevel`. |

## `Parameter`

One of a function's parameters, as written.

| Property | What it holds |
|---|---|
| `label` | The argument label callers write, or nil for `_`: `from` in `load(from url: URL)`. |
| `name` | The name inside the function: `url` there. |
| `type` | The `TypeName`, such as `URL` or `inout [Int]`, without a variadic's `...`. |
| `isVariadic` | Whether it's variadic. |
| `defaultValue` | The default value's spelling, or nil. |
| `location` | The line of its label, or of its first attribute. |

## `Attribute`

| Property | What it holds |
|---|---|
| `name` | The name without the `@`, such as `MainActor` or `available`. |
| `arguments` | What its parentheses hold, such as `*, deprecated`, or nil. |
| `location` | The line of the `@`. |

## `TypeDeclaration`

A struct, class, enum, actor or protocol (`kind`, a `TypeDeclaration.Kind`).

| Property | What it holds |
|---|---|
| `kind` | `.struct`, `.class`, `.enum`, `.actor` or `.protocol`. |
| `name` | The name. |
| `access` | Its `AccessLevel`. |
| `isFinal` | Whether it's `final`. |
| `inheritedTypes` | The `TypeName`s after the colon, in order: superclass, protocols, raw value type. |
| `attributes` | Its `Attribute`s, in order. |
| `members` | The `Member`s of its own braces, in source order; an extension's are in `SwiftFile.memberBlocks`. |
| `location` | The line of its name. |
| `lines` | From its first attribute or modifier to its closing brace. |
| `syntax` | Its declaration's node. |

## `MemberBlock`

A type's or an extension's braces, with what they hold in source order:
what a rule about order reads.

| Property | What it holds |
|---|---|
| `owner` | `.type(kind, name:)` or `.extension(typeName)`, a `MemberBlock.Owner`. |
| `access` | The owner's `AccessLevel`. |
| `inheritedTypes` | The owner's inherited types: a type's, or the conformances an extension adds. |
| `attributes` | The owner's `Attribute`s. |
| `members` | The `Member`s, in source order, every branch of an `#if` included. |
| `functions` | The members that are `func`s, as `FunctionDeclaration`s. |
| `location` | The line of the owner's name, or of the extended type. |
| `lines` | The owner's lines. |
| `syntax` | Its `MemberBlockSyntax`, whose parent is the owner's declaration. |

## `Member`

One name a member block declares: `var a, b` is two.

| Property | What it holds |
|---|---|
| `kind` | A `Member.Kind`: `.function`, `.initializer`, `.deinitializer`, `.subscript`, `.property`, `.case`, `.type`, `.typeAlias`, `.associatedType` or `.macroExpansion`. |
| `name` | The name: `init`, `deinit` and `subscript` for those kinds. |
| `access` | Its `AccessLevel`. |
| `isStatic` | Whether it's `static` or `class`. |
| `isConditional` | Whether it's inside an `#if` in its block. |
| `location` | The line of its name. |
| `lines` | The whole declaration's lines. |

## `Import`

| Property | What it holds |
|---|---|
| `module` | The module, the path's first component: `Models` for `import struct Models.Item`. |
| `path` | The whole path, such as `Models.Item`. |
| `kind` | The kind a scoped import names, such as `struct`, or nil. |
| `attributes` | Its `Attribute`s, such as `testable`. |
| `access` | The access level it writes out, such as `public` in `public import`, or nil. |
| `isConditional` | Whether it's inside an `#if`. |
| `location` | The line of the `import` keyword. |

## `TypeName`

A type as spelled: `[String]` and `Array<String>` are different names.
A string literal is one, so `returnType == "LoadResult"` reads as it says.

| Property | What it holds |
|---|---|
| `spelling` | The spelling without comments, each run of whitespace between tokens one space. |

## `AccessLevel`

| Property | What it holds |
|---|---|
| `level` | An `AccessLevel.Level`, ordered from `.private` to `.open`, so `>= .public` reads as it says. |
| `isExplicit` | Whether the declaration writes it out. One that doesn't has the level Swift gives it where it stands, read from the source alone. |

## `SwiftSourceScope`

Which of a check's findings `Rule.swiftSource` keeps (see the README's
[Which findings are kept](../README.md#which-findings-are-kept)).

| Case | Keeps a finding when |
|---|---|
| `changedDeclarations` | a declaration that judges its line changed. The default, for a rule about one declaration. |
| `changedTypes` | the type or extension around its line changed, and every finding outside any type. For a rule about order or siblings. |
| `changedFiles` | always, in a file the pull request changed. For a rule about the file. |
