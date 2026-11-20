import Steward
import SwiftSyntax

extension Rule {
    /// A rule that checks the Swift source of each file the pull request
    /// creates or changes whose head path matches `pattern`, and keeps the
    /// findings about what changed.
    ///
    /// ```swift
    /// Rule.swiftSource("Async loaders") { file in
    ///     file.functions
    ///         .filter { $0.signature.returnType == "LoadResult" && !$0.signature.isAsync }
    ///         .map { function in
    ///             .failure("\(Markdown.codeSpan(function.name)) returns `LoadResult`, so it's `async`.",
    ///                      at: function.location)
    ///         }
    /// }
    /// ```
    ///
    /// It reads each file as `Rule.changedFiles` does, at the head, with
    /// the same `excluding`, `limit` and `reportingSkipsAs`: a link, a
    /// submodule or a file over `limit` is skipped, a finding of
    /// `skipKind`. Then, for each file, it writes the log line
    /// "<rule>: checking <path>", so that the log of a run that dies names
    /// the rule and the file it died in, and:
    ///
    /// - Source with syntax errors is skipped too, and `check` isn't
    ///   called: a finding of `skipKind` from `Finding.skipped`, "with
    ///   syntax errors", and the log line
    ///   "<rule>: skipped <path>, with syntax errors". A file the compiler
    ///   builds can have them: one with code for a later compiler inside
    ///   an inactive `#if compiler(>=…)`.
    /// - Source that `SwiftFile` refuses, such as one nested past what the
    ///   parser reads safely, or whose reading runs out of time, is a
    ///   failure whatever `skipKind` is: a file skipped for it would let a
    ///   pull request hide from every rule with one construct.
    /// - Otherwise `check` runs, and `scope` decides which of its findings
    ///   are kept: by default, those in declarations the pull request
    ///   changed. `SwiftSourceScope` says which rules want which scope.
    ///
    /// `check` runs synchronously on a thread of its own with a 64 MiB
    /// stack, after the file is read, so a recursive walk in it, such as a
    /// `SyntaxVisitor` over `file.syntax`, has the stack the tree needs.
    /// The reading has a time limit, and the check has none, as a rule's
    /// check has none in Steward. On that thread, task-local values don't
    /// reach the check: `Task.isCancelled` is false there, and a test's
    /// `#expect` there isn't tied to its test. What `check` throws is the
    /// rule's failure, and no file after it is checked, so a check returns
    /// a finding for a problem in a file and throws only for what should
    /// stop the rule.
    ///
    /// - Parameters:
    ///   - name: Names the rule in the report and the log.
    ///   - pattern: The files to check, by their path at the head.
    ///   - excluded: Files among them not to check.
    ///   - scope: Which of `check`'s findings to keep.
    ///   - limit: The most bytes of a file to read; a larger one is skipped.
    ///   - skipKind: The kind of the finding for a file the rule skips.
    ///   - check: The findings in one file.
    public static func swiftSource(
        _ name: String,
        in pattern: PathPattern = "**/*.swift",
        excluding excluded: PathPattern? = nil,
        reporting scope: SwiftSourceScope = .changedDeclarations,
        limit: Int = FileContents.defaultLimit,
        reportingSkipsAs skipKind: Finding.Kind = .warning,
        _ check: @escaping @Sendable (SwiftFile) throws -> [Finding]
    ) -> Rule {
        swiftSource(
            name, in: pattern, excluding: excluded, reporting: scope, limit: limit, reportingSkipsAs: skipKind
        ) { file, _ in
            try check(file)
        }
    }

    /// A rule that checks Swift source as
    /// `swiftSource(_:in:excluding:reporting:limit:reportingSkipsAs:_:)`
    /// does, with a check that also writes to the run's log.
    ///
    /// A file the check passes over itself is the check's to report, with
    /// `Finding.skipped(_:_:by:as:)` and a log line, as the rule reports
    /// the files it skips.
    public static func swiftSource(
        _ name: String,
        in pattern: PathPattern = "**/*.swift",
        excluding excluded: PathPattern? = nil,
        reporting scope: SwiftSourceScope = .changedDeclarations,
        limit: Int = FileContents.defaultLimit,
        reportingSkipsAs skipKind: Finding.Kind = .warning,
        _ check: @escaping @Sendable (SwiftFile, Log) throws -> [Finding]
    ) -> Rule {
        let reading = SwiftSourceReading(rule: name, scope: scope, skipKind: skipKind, gate: .shared, check: check)
        return changedFiles(
            name, in: pattern, excluding: excluded, limit: limit, reportingSkipsAs: skipKind
        ) { file, log in
            try await reading.findings(for: file, log: log)
        }
    }
}

/// What `Rule.swiftSource` does with one changed file.
struct SwiftSourceReading: Sendable {
    var rule: String
    var scope: SwiftSourceScope
    var skipKind: Finding.Kind
    var gate: ParseGate
    /// The time the reading of a file gets; nil for `SwiftFile`'s, which
    /// grows with the file.
    var timeLimit: Duration?
    var check: @Sendable (SwiftFile, Log) throws -> [Finding]
    /// Reads a file within the time limit: `read(_:_:scope:)`, or in a test
    /// one that takes as long as the test needs.
    var read: @Sendable (_ source: String, _ changed: ChangedFile, _ scope: SwiftSourceScope) -> Read = Self.read

    init(
        rule: String,
        scope: SwiftSourceScope,
        skipKind: Finding.Kind,
        gate: ParseGate,
        timeLimit: Duration? = nil,
        check: @escaping @Sendable (SwiftFile, Log) throws -> [Finding]
    ) {
        self.rule = rule
        self.scope = scope
        self.skipKind = skipKind
        self.gate = gate
        self.timeLimit = timeLimit
        self.check = check
    }

    /// A file as the reading leaves it, within the time limit.
    enum Read: Sendable {
        case refused(SwiftFile.Refusal)
        case damaged
        case read(SwiftFile, ScopedFindings)
    }

    /// A file as the check leaves it.
    private enum Checked: Sendable {
        case refused(SwiftFile.Refusal)
        case damaged
        case threw(any Error)
        case checked([Finding])
    }

    func findings(for changed: ChangedFile, log: Log) async throws -> [Finding] {
        // First, so that the log of a run that dies here names the rule
        // and the file: rules run one after another.
        log.write("\(rule): checking \(changed.path)")
        let source = String(decoding: changed.contents, as: UTF8.self)
        if let excess = NestingScan.firstExcess(in: source) {
            return [refused(changed.path, .nestingTooDeep(excess.shape, line: excess.line, limit: excess.shape.limit))]
        }
        guard gate.isOpen else {
            return [refused(changed.path, .earlierParseStillRunning)]
        }
        let limit = timeLimit ?? SwiftFile.timeLimit(forUTF8Count: source.utf8.count)
        let checked = await LargeStack.value(timeLimit: limit, gate: gate) { [read, scope] in
            read(source, changed, scope)
        } then: { [check] read in
            Self.check(read, with: check, log: log)
        }
        switch checked ?? .refused(.timedOut(limit: limit)) {
        case .refused(let refusal):
            return [refused(changed.path, refusal)]
        case .damaged:
            log.write("\(rule): skipped \(changed.path), with syntax errors")
            return [.skipped(changed.path, "with syntax errors", by: rule, as: skipKind)]
        case .threw(let error):
            throw error
        case .checked(let findings):
            return findings
        }
    }

    /// The file `source` holds, read and indexed for `scope`, within the
    /// time limit.
    static func read(_ source: String, _ changed: ChangedFile, scope: SwiftSourceScope) -> Read {
        switch SwiftFile.parseOnThisThread(source: source, path: changed.path) {
        case .failure(let refusal):
            .refused(refusal)
        case .success(let file) where file.syntax.hasError:
            .damaged
        case .success(let file):
            .read(file, ScopedFindings(file: file, changed: changed, scope: scope))
        }
    }

    /// What `check` finds in a file it read, and the scope keeps, with no
    /// time limit.
    private static func check(
        _ read: Read,
        with check: @Sendable (SwiftFile, Log) throws -> [Finding],
        log: Log
    ) -> Checked {
        switch read {
        case .refused(let refusal):
            return .refused(refusal)
        case .damaged:
            return .damaged
        case .read(let file, let scoped):
            do {
                return .checked(scoped.kept(try check(file, log)))
            } catch {
                return .threw(error)
            }
        }
    }

    /// The failure for a file `SwiftFile` refused, at the file.
    private func refused(_ path: String, _ refusal: SwiftFile.Refusal) -> Finding {
        .failure(
            "Rule “\(Markdown.escaped(rule))” couldn't read \(Markdown.codeSpan(path)). \(refusal)",
            at: Location(path: path)
        )
    }
}

/// Which of a check's findings about one file a scope keeps.
struct ScopedFindings: Sendable {
    let path: String
    let scope: SwiftSourceScope
    let changedLineNumbers: LineRangeSet
    let lineNumbersAfterDeletions: LineRangeSet
    let index: DeclarationIndex
    let lineCount: Int

    /// Whether the pull request changed any line in `lineRange`: added or
    /// rewrote one, or deleted lines just before one.
    func changed(_ lineRange: ClosedRange<Int>) -> Bool {
        changedLineNumbers.overlaps(lineRange) || lineNumbersAfterDeletions.overlaps(lineRange)
    }

    /// The findings among `findings` the scope keeps, in their order,
    /// each line judged once: a check may report on thousands of
    /// declarations that share one line.
    func kept(_ findings: [Finding]) -> [Finding] {
        let lineNumbers = Set(findings.compactMap(judgedLine(of:)))
        let decisions = Dictionary(uniqueKeysWithValues: lineNumbers.map { ($0, keeps(line: $0)) })
        return findings.filter { finding in judgedLine(of: finding).map { decisions[$0] ?? true } ?? true }
    }

    func keeps(_ finding: Finding) -> Bool {
        judgedLine(of: finding).map(keeps(line:)) ?? true
    }

    /// The line the scope judges `finding` by, or nil when it keeps the
    /// finding whatever changed.
    private func judgedLine(of finding: Finding) -> Int? {
        // A scope narrows by line: a finding with none, or about another
        // file, is about what no line of this file holds. Paths compare by
        // their bytes, as git tells them apart: `==` takes a name's
        // precomposed and decomposed spellings for one.
        guard scope != .changedFiles, let location = finding.location,
              location.path.utf8.elementsEqual(path.utf8)
        else { return nil }
        return location.line
    }

    /// Whether the scope keeps a finding at `line`.
    private func keeps(line: Int) -> Bool {
        // A line the file doesn't have, a rule's bug, is a loose line, and
        // never an index.
        let units = 1...lineCount ~= line ? index.units(judging: line) : []
        guard !units.isEmpty else {
            // A loose line is at the top of the file, whose container is
            // the file.
            return scope == .changedTypes || changed(line...line)
        }
        // Each unit with a token on the line judges it: a change to any
        // keeps the finding, the safe side.
        guard scope == .changedTypes else {
            return units.contains { changed(index.units[$0].lineRange) }
        }
        return units.contains { unit in
            index.container(of: unit, line: line).map { changed(index.units[$0].lineRange) } ?? true
        }
    }
}

extension ScopedFindings {
    init(file: SwiftFile, changed: ChangedFile, scope: SwiftSourceScope) {
        self.init(
            path: changed.path,
            scope: scope,
            changedLineNumbers: changed.changedLineNumbers,
            lineNumbersAfterDeletions: changed.lineNumbersAfterDeletions,
            index: DeclarationIndex(file: file),
            lineCount: file.sourceLines.count
        )
    }
}
