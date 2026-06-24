#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

app_name="ClipboardApp"
configuration="${CONFIGURATION:-release}"
version="${VERSION:-0.1.0}"
dist_dir="${DIST_DIR:-$PWD/dist}"
package_name="${PACKAGE_NAME:-${app_name}-v${version}-macos}"
run_verify="${RUN_VERIFY:-1}"
require_stable_code_signing="${REQUIRE_STABLE_CODE_SIGNING:-1}"

if [[ "$run_verify" == "1" ]]; then
  Scripts/verify.sh >&2
else
  echo "warning: skipping verification because RUN_VERIFY=$run_verify" >&2
fi

app_path="$(
  VERSION="$version" \
  CONFIGURATION="$configuration" \
  REQUIRE_STABLE_CODE_SIGNING="$require_stable_code_signing" \
  Scripts/build-app-bundle.sh
)"

if [[ ! -d "$app_path" ]]; then
  echo "error: app bundle was not produced: $app_path" >&2
  exit 1
fi

mkdir -p "$dist_dir"

zip_name="$package_name.zip"
zip_path="$dist_dir/$zip_name"
sha_name="$zip_name.sha256"
sha_path="$dist_dir/$sha_name"

rm -f "$zip_path" "$sha_path"
ditto -c -k --keepParent --norsrc --noextattr "$app_path" "$zip_path"

(
  cd "$dist_dir"
  shasum -a 256 "$zip_name" > "$sha_name"
)

echo "release package: $zip_path"
echo "checksum: $sha_path"
codesign -dv --verbose=4 "$app_path" >&2
