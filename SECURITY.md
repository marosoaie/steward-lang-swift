# Security policy

steward-lang-swift parses Swift source that a pull request's author
controls: a Dangerfile's rules read the files the pull request creates or
changes, and what a rule finds can end up in a public comment. It is
meant to read any such file without crashing or hanging the run, and to
read nothing but the files a rule asks for. Nothing in it reads a pull
request's files yet; what it guarantees, and how that is tested, will be
listed here as that code lands.

Steward, which runs the rules and posts what they find, has
[its own policy](https://github.com/marosoaie/swift-steward/blob/main/SECURITY.md).

## What counts as a vulnerability

Please report privately any Swift source, file or pull request that makes
steward-lang-swift:

- crash, trap, or read or write memory out of bounds;
- take time or memory out of proportion to the file's size, or hang;
- read anything other than a file the pull request changed, such as the
  target of a symlink;
- put text in a finding that its rule didn't write, such as a mention or
  a link.

A file that steward-lang-swift reads differently from the Swift compiler,
without any of the effects above, is an ordinary bug: please open an
issue.

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
