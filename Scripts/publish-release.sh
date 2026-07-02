#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Build, package, and publish a stable-signed Clipboard release, then update the
# Homebrew cask in the local tap clone.
#
#   VERSION       semantic version, e.g. 0.2.0   (or pass as the first argument)
#   TAP_REPO_DIR  path to a local clone of anlostsheep/homebrew-clipboard
#
# Build + stable signing stay local so Accessibility permission stays stable
# across updates. Only `gh` publishing touches the network.

version="${1:-${VERSION:-}}"
tap_repo_dir="${TAP_REPO_DIR:-}"
release_branch="${RELEASE_BRANCH:-master}"
cask_relpath="${CASK_RELPATH:-Casks/clipboardapp.rb}"

die() { echo "error: $*" >&2; exit 1; }

# --- Tier 1: argument validation (hermetic; unit-tested) ---
[[ -n "$version" ]] || die "VERSION is required (pass as arg or env), e.g. VERSION=0.2.0"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 1.2.3 (got: $version)"
[[ -n "$tap_repo_dir" ]] || die "TAP_REPO_DIR is required (local clone of anlostsheep/homebrew-clipboard)"

tag="v$version"

# --- Tier 2: environment + git state (verified during go-live dry run) ---
[[ -d "$tap_repo_dir/.git" ]] || die "TAP_REPO_DIR is not a git repo: $tap_repo_dir"
cask_file="$tap_repo_dir/$cask_relpath"
[[ -f "$cask_file" ]] || die "cask not found in tap: $cask_file"

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is not installed"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run: gh auth login"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$current_branch" == "$release_branch" ]] || die "must be on '$release_branch' (on '$current_branch')"

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "git working tree is not clean; commit or stash first"
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "git tag $tag already exists"
fi

if gh release view "$tag" >/dev/null 2>&1; then
  die "GitHub release $tag already exists"
fi

# --- Build + package locally (stable signing required) ---
echo "==> building and packaging $tag (stable signed)"
package_output="$(VERSION="$version" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/package-release.sh)"
echo "$package_output"

zip_path="$(printf '%s\n' "$package_output" | sed -nE 's/^release package: (.*)$/\1/p')"
sha_path="$(printf '%s\n' "$package_output" | sed -nE 's/^checksum: (.*)$/\1/p')"
[[ -f "$zip_path" ]] || die "release zip not found: $zip_path"
[[ -f "$sha_path" ]] || die "checksum file not found: $sha_path"

sha256_value="$(awk '{print $1}' "$sha_path")"
[[ "$sha256_value" =~ ^[0-9a-f]{64}$ ]] || die "could not read sha256 from $sha_path"

# --- Publish to the network: tag, release, cask (local artifacts already complete) ---
# If a step after the tag push fails, delete the remote tag before re-running:
#   git push origin ":refs/tags/$tag" && git tag -d "$tag"
echo "==> tagging $tag"
git tag -a "$tag" -m "Release $tag"
git push origin "$tag"

echo "==> creating GitHub release $tag"
notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT
cat > "$notes_file" <<EOF
Clipboard $tag — open-source beta.

This build is self-signed and not notarized. Recommended install (no Gatekeeper
prompt) is via Homebrew:

    brew tap anlostsheep/clipboard
    brew install --cask clipboardapp

Update later with:

    brew upgrade --cask clipboardapp

Direct-download users: see docs/install.md for the first-open Gatekeeper steps.
EOF

gh release create "$tag" "$zip_path" "$sha_path" --title "$tag" --notes-file "$notes_file"

echo "==> updating cask in tap"
Scripts/update-cask.sh "$cask_file" "$version" "$sha256_value"
(
  cd "$tap_repo_dir"
  git add "$cask_relpath"
  git commit -m "clipboardapp $version"
  git push
)

echo
echo "==> done. verify with:"
echo "    brew update && brew upgrade --cask clipboardapp"
echo "    shasum -a 256 -c \"$sha_path\""
