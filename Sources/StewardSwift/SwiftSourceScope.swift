/// Which of a check's findings `Rule.swiftSource` keeps: those about what
/// the pull request changed, judged by the unit of source each one is in.
///
/// Which rules want which:
///
/// - A rule about one declaration, such as "a function that returns
///   `LoadResult` is `async`", wants `changedDeclarations`, the default.
/// - A rule about order or siblings, such as "private functions come last
///   in their type", wants `changedTypes`. Under `changedDeclarations` a
///   pull request that adds a private function above an untouched public
///   one would make the public one misplaced, and the finding on it, an
///   unchanged declaration, would be dropped.
/// - A rule about the file, such as its imports or its header, wants
///   `changedFiles`.
///
/// The units are the declarations the model names and the file's top-level
/// statements: a type or an extension, a member of one, a `func` at any
/// depth, and a declaration or statement at the top of the file. A local
/// `let` or `var`, an accessor and a closure aren't units: a line in one
/// belongs to the unit around it, so a line in a function's body belongs
/// to the function. `#if` isn't one either: what's inside it belongs where
/// it would without it, and a directive's line is a line of whatever is
/// around it.
///
/// A unit counts as changed when the pull request adds or rewrites one of
/// its lines, or deletes lines inside it or directly above its first line:
/// `changedLines.overlaps(lines) || linesAfterDeletions.overlaps(lines)`.
/// Its lines, for this test only, run from the comment lines directly
/// above it, with no blank line between, so that a pull request that edits
/// only a doc comment changes what it documents; a model value's own
/// `lines` start at its first attribute or modifier.
///
/// That test has a known false positive: a deletion directly above a unit
/// marks it whatever was deleted, an attribute of its own or the whole
/// function before it, since only the base's text could tell. A deletion
/// directly below a unit's last line doesn't mark it.
///
/// A finding with no line, with no location at all, or about another
/// file is kept in every scope: a scope narrows by line, and such a
/// finding is about what no line holds, such as a file's name, which a
/// rename changes without changing a line.
public enum SwiftSourceScope: Sendable, Hashable, CaseIterable {
    /// Keep a finding when the innermost unit around its line changed; on
    /// a line in no unit, a blank or comment line between top-level items,
    /// when that line changed.
    case changedDeclarations

    /// Keep a finding when the type or extension whose braces hold its line
    /// changed anywhere. The line of the `{` is outside the braces, so a
    /// nested type's own line belongs to the type around it. At the top of
    /// the file, outside any braces, the container is the file, and every
    /// finding is kept.
    ///
    /// It keeps every finding `changedDeclarations` keeps.
    case changedTypes

    /// Keep every finding, in every file the rule checks.
    case changedFiles
}
