#!/usr/bin/env bash
# Checks that the version in $1 can be released, given the repository's tag
# names, one per line, on standard input: it must be MAJOR.MINOR.PATCH,
# with no leading zeros and no `v` (the release workflow adds it), untagged
# in either form, and greater than every version tagged so far, with or
# without the `v`. Pre-release and other tags don't count.
#
# The release workflow pipes `git ls-remote --tags --refs origin` into it;
# locally:
#   git ls-remote --tags --refs origin | sed 's|.*refs/tags/||' \
#     | .github/scripts/check-release-version.sh 0.2.0
set -euo pipefail

version=${1-}
number='(0|[1-9][0-9]*)'
if [[ ! "$version" =~ ^$number\.$number\.$number$ ]]; then
  printf 'Not MAJOR.MINOR.PATCH, without a v: %q\n' "$version" >&2
  exit 1
fi

tags=$(cat)
if grep -Fxq -e "$version" -e "v$version" <<<"$tags"; then
  echo "$version is already tagged, as $version or v$version" >&2
  exit 1
fi

# Every MAJOR.MINOR.PATCH tag, with or without the v, compared field by
# field as numbers.
newest=$(
  { grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' <<<"$tags" || true; } \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1
)
# A stable sort with the version first leaves it last only if it's greater
# as numbers, not merely equal, as 1.0.0 is to a tag 01.0.0.
if [[ -n "$newest" ]]; then
  last=$(printf '%s\n%s\n' "$version" "$newest" | sort -s -t. -k1,1n -k2,2n -k3,3n | tail -n 1)
  if [[ "$last" != "$version" || "$newest" == "$version" ]]; then
    echo "$version isn't greater than $newest, the newest version tagged" >&2
    exit 1
  fi
fi

echo "v$version can be released; the newest version tagged so far is ${newest:-none}."
