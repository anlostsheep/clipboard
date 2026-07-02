#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Build, package, and publish a stable-signed Clipboard release, then update the
# Homebrew cask in the local tap clone.
#
#   VERSION       semantic version, e.g. 0.1.0   (or pass as the first argument)
#   TAP_REPO_DIR  path to a local clone of anlostsheep/homebrew-clipboard
#
# Build + stable signing stay local so Accessibility permission stays stable
# across updates. Only the release publish (curl to the GitHub REST API) touches
# the network. The GitHub PAT is read from the macOS keychain (git's osxkeychain
# credential entry for github.com) and is never printed.

version="${1:-${VERSION:-}}"
tap_repo_dir="${TAP_REPO_DIR:-}"
release_branch="${RELEASE_BRANCH:-master}"
cask_relpath="${CASK_RELPATH:-Casks/clipboardapp.rb}"

die() { echo "error: $*" >&2; exit 1; }

# --- Tier 1: argument validation (hermetic; unit-tested) ---
[[ -n "$version" ]] || die "VERSION is required (pass as arg or env), e.g. VERSION=0.1.0"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION must look like 1.2.3 (got: $version)"
[[ -n "$tap_repo_dir" ]] || die "TAP_REPO_DIR is required (local clone of anlostsheep/homebrew-clipboard)"

tag="v$version"

# --- Tier 2: environment + git state (verified during go-live) ---
[[ -d "$tap_repo_dir/.git" ]] || die "TAP_REPO_DIR is not a git repo: $tap_repo_dir"
cask_file="$tap_repo_dir/$cask_relpath"
[[ -f "$cask_file" ]] || die "cask not found in tap: $cask_file"

command -v curl >/dev/null 2>&1 || die "curl is not installed"
command -v jq >/dev/null 2>&1 || die "jq is not installed (brew install jq)"

# Resolve owner/repo from the origin remote (https or ssh form).
origin_url="$(git remote get-url origin)"
repo_slug="$(printf '%s' "$origin_url" | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
owner="${repo_slug%%/*}"
repo="${repo_slug##*/}"
[[ -n "$owner" && -n "$repo" && "$owner" != "$repo_slug" ]] || die "could not parse owner/repo from origin: $origin_url"

# Read the GitHub PAT from the macOS keychain (git osxkeychain entry). Never printed.
github_token="$(security find-internet-password -s github.com -a "$owner" -w 2>/dev/null || true)"
[[ -n "$github_token" ]] || die "no GitHub PAT in keychain for github.com/$owner (expected git credential.helper=osxkeychain)"

api="https://api.github.com/repos/$owner/$repo"
auth_header="Authorization: Bearer $github_token"
accept_header="Accept: application/vnd.github+json"

# Fail fast: the token must be able to read the repo before we build or tag.
repo_http="$(curl -sS -o /dev/null -w '%{http_code}' -H "$auth_header" -H "$accept_header" "$api")"
[[ "$repo_http" == "200" ]] || die "GitHub PAT cannot access $owner/$repo (HTTP $repo_http); check token validity/scope"

current_branch="$(git rev-parse --abbrev-ref HEAD)"
[[ "$current_branch" == "$release_branch" ]] || die "must be on '$release_branch' (on '$current_branch')"

if ! git diff --quiet || ! git diff --cached --quiet; then
  die "git working tree is not clean; commit or stash first"
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  die "git tag $tag already exists"
fi

rel_http="$(curl -sS -o /dev/null -w '%{http_code}' -H "$auth_header" -H "$accept_header" "$api/releases/tags/$tag")"
case "$rel_http" in
  404) : ;;                                   # good: release does not exist yet
  200) die "GitHub release $tag already exists" ;;
  *)   die "unexpected HTTP $rel_http checking release $tag" ;;
esac

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
# If a step after the tag push fails, delete the remote tag and any half-created
# release before re-running:
#   git push origin ":refs/tags/$tag" && git tag -d "$tag"
#   (and delete the partial GitHub release for $tag)
echo "==> tagging $tag"
git tag -a "$tag" -m "Release $tag"
git push origin "$tag"

echo "==> creating GitHub release $tag"
notes="$(cat <<EOF
Clipboard $tag — open-source beta.

This build is self-signed and not notarized. Recommended install is via Homebrew;
the cask removes the quarantine attribute after install so the app opens without a
Gatekeeper prompt:

    brew tap anlostsheep/clipboard
    brew install --cask clipboardapp

Update later with:

    brew upgrade --cask clipboardapp

Direct-download users: see docs/install.md for the first-open Gatekeeper steps.
EOF
)"

create_payload="$(jq -n --arg tag "$tag" --arg name "$tag" --arg body "$notes" \
  '{tag_name: $tag, name: $name, body: $body}')"
create_response="$(curl -sS -X POST -H "$auth_header" -H "$accept_header" "$api/releases" -d "$create_payload")"
upload_url="$(printf '%s' "$create_response" | jq -r '.upload_url // empty' | sed -E 's/\{.*\}$//')"
[[ -n "$upload_url" ]] || die "failed to create release for $tag: $(printf '%s' "$create_response" | jq -r '.message // "unknown error"')"

echo "==> uploading assets"
for asset in "$zip_path" "$sha_path"; do
  asset_name="$(basename "$asset")"
  upload_http="$(curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "$auth_header" -H "Content-Type: application/octet-stream" \
    --data-binary @"$asset" "$upload_url?name=$asset_name")"
  [[ "$upload_http" == "201" ]] || die "asset upload failed for $asset_name (HTTP $upload_http)"
done

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
