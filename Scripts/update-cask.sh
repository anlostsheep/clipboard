#!/bin/bash
set -euo pipefail

# Rewrite the version and sha256 stanzas of a Homebrew cask file in place.
# Usage: Scripts/update-cask.sh <cask-file> <version> <sha256>
#   <version>  semantic version like 1.2.3
#   <sha256>   64 lowercase hex characters
# The cask file must already contain `version "..."` and `sha256 "..."` lines.

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <cask-file> <version> <sha256>" >&2
  exit 2
fi

cask_file="$1"
version="$2"
sha256="$3"

[[ -f "$cask_file" ]] || { echo "error: cask file not found: $cask_file" >&2; exit 1; }

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must look like 1.2.3 (got: $version)" >&2; exit 1
fi

if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: sha256 must be 64 lowercase hex chars (got: $sha256)" >&2; exit 1
fi

grep -Eq '^[[:space:]]*version "[^"]*"' "$cask_file" || { echo "error: no version stanza in $cask_file" >&2; exit 1; }
grep -Eq '^[[:space:]]*sha256 "[^"]*"' "$cask_file"  || { echo "error: no sha256 stanza in $cask_file" >&2; exit 1; }

# BSD sed (macOS) in-place edit. version/sha256 are validated to safe charsets.
sed -i '' -E "s/^([[:space:]]*version )\"[^\"]*\"/\1\"$version\"/" "$cask_file"
sed -i '' -E "s/^([[:space:]]*sha256 )\"[^\"]*\"/\1\"$sha256\"/" "$cask_file"

echo "updated $cask_file -> version $version, sha256 $sha256"
