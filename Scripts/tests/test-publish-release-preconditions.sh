#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../.."

script="Scripts/publish-release.sh"
fail=0

expect_fail_msg() {
  local desc="$1" needle="$2"; shift 2
  local out rc
  set +e
  out="$("$@" 2>&1)"
  rc=$?
  set -e
  if [[ $rc -ne 0 && "$out" == *"$needle"* ]]; then
    echo "ok: $desc"
  else
    echo "FAIL: $desc (rc=$rc, out=<<$out>>)" >&2
    fail=1
  fi
}

# Argument-validation tier runs before any git/gh/network use, so these are hermetic.
expect_fail_msg "missing VERSION" "VERSION is required" \
  env -u VERSION -u TAP_REPO_DIR bash "$script"
expect_fail_msg "bad semver" "must look like" \
  env -u TAP_REPO_DIR VERSION=1.2 bash "$script"
expect_fail_msg "missing TAP_REPO_DIR" "TAP_REPO_DIR is required" \
  env -u TAP_REPO_DIR VERSION=1.2.3 bash "$script"

if [[ $fail -ne 0 ]]; then echo "TESTS FAILED" >&2; exit 1; fi
echo "ALL TESTS PASSED"
