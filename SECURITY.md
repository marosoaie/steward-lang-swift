# Security policy

steward-lang-swift parses Swift source that a pull request's author
controls: a Dangerfile's rules read the files the pull request creates or
changes, and what a rule finds can end up in a public comment. It is
meant to read any such file without crashing or hanging the run, to refuse
a file it can't read safely rather than skip it, and to read nothing but
the files a rule asks for. The rule that reads files from a pull request
isn't built yet; what `SwiftFile`, which parses one, does is below.

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
  parser's nesting limit is 20, not 256, and it's about 30 times slower.

## What SwiftFile does

- **It refuses what it can't read safely.** A scan of the bytes, before
  parsing, refuses a source that nests `[`, `<`, `#if` or interpolations
  past fixed limits. A tree deeper than 2,048 levels is refused after
  parsing, so a rule's own recursive walk has the stack for it. A parse
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

## What it doesn't protect against

- **The scan is a heuristic, not a lexer.** A source crafted to put it out
  of step with the parser can get past it. The deadline is the backstop
  for time, but nothing in the process can catch a stack overflow or an
  exhausted memory: such a source still ends the run. That fails the
  check, which is closed, but loses the run's report. The containment for
  that is parsing in a process of its own, which needs a hook in Steward;
  it's the next step if the list of hazards above grows.
- **A parse that runs out of time keeps running.** Nothing can stop the
  thread, so it holds a core until it ends or the run exits, and no other
  file is parsed meanwhile: each is refused.
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

steward-lang-swift is pre-1.0, and nothing is released yet. Fixes land on
`main` and ship in the next release; earlier releases don't get
backported fixes.
