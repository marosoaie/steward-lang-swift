# Security policy

steward-lang-swift parses Swift source that a pull request's author
controls: a Dangerfile's rules read the files the pull request creates or
changes, and what a rule finds can end up in a public comment. It is
meant to read any such file without crashing or hanging the run, to refuse
a file it can't read safely rather than skip it, and to read nothing but
the files a rule asks for. What `SwiftFile`, which parses a file, and
`Rule.swiftSource`, which reads the pull request's, do is below.

Steward, which runs the rules and posts what they find, has
[its own policy](https://github.com/marosoaie/swift-steward/blob/main/SECURITY.md).

## The parser it builds on

swift-syntax's parser recovers from source that isn't valid Swift, but on
hostile source it isn't bounded by itself. Measured with swift-syntax 604:

- Nested `[` that open array literals or array types double the parse time
  with each level, in every build configuration: 26 levels take seconds,
  40 would take days.
- Generic arguments, `#if` blocks and string interpolations recurse past
  the parser's nesting limit: on the 512 KiB stacks that `async` code gets
  on macOS, 100 levels of `A<A<…` overflow the stack in a release build,
  and a few thousand overflow a 64 MiB one; 100,000 nested interpolations
  exhaust memory.
- In a debug build, which is how a Dangerfile is usually built, the
  parser's nesting limit is 20, not 256, and a read is about 40 times
  slower (docs/performance.md).

## What SwiftFile does

- **It refuses what it can't read safely.** A scan of the bytes, before
  parsing, refuses a source that nests `[`, `<`, `#if` or interpolations
  past fixed limits. After parsing, a source that went past the parser's
  nesting limit is refused, since the parser leaves the rest of such a
  file unread, and so is a tree deeper than 512 levels, so that a rule's
  own recursive walk has the stack for it on any thread. A parse
  that runs past its deadline (two seconds, and 50 µs for each byte) is
  refused too. Each refusal is a thrown `SwiftFile.Refusal` that says
  what went past which limit, and is meant to fail the rule that asked:
  a file that was skipped instead would let a pull request hide from
  every rule with one construct.
- **It parses on a stack of its own.** The parse runs on a thread with a
  64 MiB stack, whatever thread asked, with the parser's nesting limit at
  256 in every build configuration. The package's own walks over the
  tree keep their own stack, so a tree as deep as the source is long
  can't overflow one.
- **It reads source that isn't valid Swift.** Truncated, mutated or
  damaged source is parsed with the parser's repairs, and
  `syntax.hasError` says so. That isn't a refusal.
- **Its line numbers are git's.** A line ends at a line feed, so a
  location names the line a pull request's diff shows, and a lone `\r`
  can't shift it.

## What Rule.swiftSource does

- **A refusal is a failure.** A file `SwiftFile` refuses, or whose reading
  runs past its deadline, is a failure of the rule, whatever kind the
  rule reports its skips as.
- **A file with syntax errors is a skip,** a finding of the rule's skip
  kind (a warning unless the Dangerfile says otherwise) and a log line,
  and the rule's check never sees it. So a pull request can keep a file
  from every Swift rule with a syntax error, and the build fails on most
  of those. Not on all: the compiler doesn't parse an inactive
  `#if compiler(>=…)` block, so a file that builds can hold one. The skip
  shows in the summary; a Dangerfile that wants it to fail the check sets
  `reportingSkipsAs: .failure`.
- **It names each file before reading it.** Each rule logs
  "<rule>: checking <path>" before it reads a file, and rules run one
  after another, so the log of a run that dies names the rule and the file
  it died in.
- **The deadline is the reading's.** It covers the parse, the model and
  the scopes' index, after the nesting scan, one linear pass on the
  rule's own thread before them; the rule's check runs after it, on the
  same 64 MiB thread, with no limit, as a check in Steward has none.

## What it doesn't protect against

- **The scan stops accidents, not an author who means it.** It's a
  heuristic, not a lexer: one line can put it out of step with the parser,
  and a second can then crash the run or exhaust its memory. The deadline
  is the backstop for time, but nothing in the process can catch a stack
  overflow or an exhausted memory. Such a run fails its check, which is
  closed, but loses its report. With steward-action v0.1.1, its latest
  release, the summary comment from an earlier push stays as it was, and
  a first push gets none; steward-action's main branch replaces the
  comment with "Steward didn't finish" and the reason (steward-action#11),
  but no release has it yet. The log's last "checking" line names the
  rule and the file. The containment is parsing in a process of its own,
  which needs a hook in Steward; whether rules that read pull requests'
  files wait for it is the maintainer's call.
- **A rule's check has no time limit.** A hostile file can make a check
  that's slower than linear take long, and the job then runs to the
  workflow's limit: six hours unless the workflow sets `timeout-minutes`.
  Set it. That's true of every rule in Steward; a limit per rule would be
  Steward's runner's. A check can be quadratic without looking it: the
  names a declaration declares share its attributes and its doc comment,
  so a check that reads each member's `attributes`, such as one looking
  for `@Published`, does names × attributes work on a declaration with
  thousands of each, and one that searches each member's
  `documentation`, names × the comment's length. So does hashing the
  members, as `Set(members)` does, since a member's hash takes in both.
  In a release build, such a check takes ten seconds on a 128 KiB file of
  that shape and nine minutes on a 1 MiB one; a debug build, as a
  Dangerfile usually is, is slower.
- **It can refuse honest source**, rarely: 513 comparisons with no `{`,
  `}`, `;` or assignment between them, or a run of regex literals holding
  an unescaped `[`. A refusal fails the rule, so please report one as an
  ordinary bug.
- **A parse that runs out of time keeps running.** Nothing can stop the
  thread, so it holds a core until it ends or the run exits, and no other
  file is parsed meanwhile: each is refused, a failure of every Swift rule
  that reads it.
- **Its own tests are the measure.** Real files read whole, cut short and
  mutated with seeded edits, the shapes above nested tens of thousands
  deep, and each limit, in both directions.

## What counts as a vulnerability

Please report privately any Swift source, file or pull request that makes
steward-lang-swift:

- crash, trap, or read or write memory out of bounds;
- take time or memory out of proportion to the file's size, or hang;
- hide a file's declarations from a rule without refusing the file;
- read anything other than a file the pull request changed, such as the
  target of a symlink;
- put text in a finding that its rule didn't write, such as a mention or
  a link.

A file that steward-lang-swift reads differently from the Swift compiler,
without any of the effects above, is an ordinary bug: please open an
issue. So is honest source that's refused.

## Reporting a vulnerability

Report it through GitHub's private vulnerability reporting: on the
repository's **Security** tab, choose **Report a vulnerability**. The
report stays private between you and the maintainer until a fix is
published. Include the source that triggers the problem, or a way to
make it, and the steward-lang-swift version or commit.

## Supported versions

steward-lang-swift is pre-1.0, at 0.1. Fixes land on `main` and ship in
the next release; earlier releases don't get backported fixes, and a
published release is never changed.
