#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

script="Scripts/update-cask.sh"
fail=0

assert() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (want '$want', got '$got')" >&2
    fail=1
  fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cask="$work/clipboard.rb"

make_cask() {
  cat > "$cask" <<'RUBY'
cask "clipboard" do
  version "0.0.0"
  sha256 "1111111111111111111111111111111111111111111111111111111111111111"

  url "https://example.com/v#{version}/app.zip"
end
RUBY
}

new_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

# Happy path: version + sha256 rewritten
make_cask
bash "$script" "$cask" "1.2.3" "$new_sha" >/dev/null
ver="$(sed -nE 's/^[[:space:]]*version "([^"]*)".*/\1/p' "$cask")"
sha="$(sed -nE 's/^[[:space:]]*sha256 "([^"]*)".*/\1/p' "$cask")"
assert "version rewritten" "$ver" "1.2.3"
assert "sha256 rewritten" "$sha" "$new_sha"

run_expect_fail() {
  local desc="$1"; shift
  local rc
  set +e
  "$@" >/dev/null 2>&1
  rc=$?
  set -e
  assert "$desc" "$([[ $rc -ne 0 ]] && echo nonzero || echo zero)" "nonzero"
}

make_cask; run_expect_fail "invalid version rejected" bash "$script" "$cask" "1.2" "$new_sha"
make_cask; run_expect_fail "invalid sha rejected"     bash "$script" "$cask" "1.2.3" "tooshort"
run_expect_fail "missing file rejected"               bash "$script" "$work/nope.rb" "1.2.3" "$new_sha"

if [[ $fail -ne 0 ]]; then echo "TESTS FAILED" >&2; exit 1; fi
echo "ALL TESTS PASSED"
