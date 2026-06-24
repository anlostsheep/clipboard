# Distribution Trust Chain (Free Path / Homebrew) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a free-path distribution chain so strangers install Clipboard with one clean Homebrew command (no Gatekeeper prompt) and update via `brew upgrade --cask`, while keeping zero in-app network calls and stable self-signed signing.

**Architecture:** A new `Scripts/publish-release.sh` orchestrates the existing `package-release.sh` (local, stable-signed build) and then publishes a GitHub Release with `gh` and rewrites a Homebrew cask. The cask lives in a separate tap repo `anlostsheep/homebrew-clipboard`, seeded from `packaging/homebrew/` in this repo. Build + signing stay local (stable signing keeps Accessibility permission stable across updates); only `gh` publishing touches the network. The app gains no network code.

**Tech Stack:** Bash, Homebrew Cask (Ruby DSL), GitHub CLI (`gh`), GitHub Actions, existing SwiftPM build/sign scripts.

**Reference spec:** `docs/superpowers/specs/2026-06-24-distribution-trust-chain-homebrew-design.md`

---

## File Structure

New files (this repo):
- `Scripts/update-cask.sh` — pure text transform: rewrite a cask's `version` + `sha256`. One responsibility, unit-tested.
- `Scripts/publish-release.sh` — release orchestrator: preconditions → `package-release.sh` → tag → `gh release` → `update-cask.sh` → push tap.
- `Scripts/tests/test-update-cask.sh` — hermetic tests for `update-cask.sh`.
- `Scripts/tests/test-publish-release-preconditions.sh` — hermetic tests for the argument-validation tier of `publish-release.sh`.
- `packaging/homebrew/Casks/clipboard.rb` — seed cask (source of truth for bootstrapping the tap).
- `packaging/homebrew/.github/workflows/audit.yml` — tap CI: `brew style` + `brew audit`.
- `packaging/homebrew/README.md` — tap usage/maintenance notes.

Modified files (this repo):
- `docs/install.md` — Homebrew-first install, direct-download fallback retained.
- `docs/release-process.md` — `publish-release.sh` flow + tap maintenance.
- `README.md` — install section leads with `brew install --cask`.
- `docs/manual-acceptance-checklist.md` — new distribution acceptance items.

Out of this repo (operational, Task 8): the tap repo `anlostsheep/homebrew-clipboard` is created and seeded on GitHub; the first real release is published.

**Scope note:** `build-app-bundle.sh` already writes `VERSION` into `Info.plist`, so the "version single source of truth" requirement needs no build-script change — `publish-release.sh` owns the version and creates the tag. Do not edit `build-app-bundle.sh`.

---

### Task 1: `update-cask.sh` — pure cask version/sha rewriter (TDD)

**Files:**
- Create: `Scripts/tests/test-update-cask.sh`
- Create: `Scripts/update-cask.sh`

- [ ] **Step 1: Write the failing test**

Create `Scripts/tests/test-update-cask.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x Scripts/tests/test-update-cask.sh && bash Scripts/tests/test-update-cask.sh`
Expected: FAIL — the happy-path line errors because `Scripts/update-cask.sh` does not exist (`bash: Scripts/update-cask.sh: No such file or directory`), non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `Scripts/update-cask.sh`:

```bash
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x Scripts/update-cask.sh && bash Scripts/tests/test-update-cask.sh`
Expected: PASS — ends with `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Lint**

Run: `bash -n Scripts/update-cask.sh && { command -v shellcheck >/dev/null && shellcheck Scripts/update-cask.sh Scripts/tests/test-update-cask.sh || echo "shellcheck not installed (optional: brew install shellcheck)"; }`
Expected: no syntax errors; shellcheck clean or the skip message.

- [ ] **Step 6: Commit**

```bash
chmod +x Scripts/update-cask.sh Scripts/tests/test-update-cask.sh
git add Scripts/update-cask.sh Scripts/tests/test-update-cask.sh
git commit -m "build: add cask version/sha rewriter with tests"
```

---

### Task 2: Seed Homebrew cask + tap CI + tap README

**Files:**
- Create: `packaging/homebrew/Casks/clipboard.rb`
- Create: `packaging/homebrew/.github/workflows/audit.yml`
- Create: `packaging/homebrew/README.md`

- [ ] **Step 1: Create the seed cask**

Create `packaging/homebrew/Casks/clipboard.rb`:

```ruby
cask "clipboard" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/anlostsheep/clipboard/releases/download/v#{version}/ClipboardApp-v#{version}-macos.zip"
  name "Clipboard"
  desc "Native macOS clipboard manager"
  homepage "https://github.com/anlostsheep/clipboard"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "ClipboardApp.app"

  zap trash: [
    "~/Library/Application Support/com.local.clipboard-manager",
    "~/Library/Preferences/com.local.clipboard-manager.plist",
  ]

  caveats <<~EOS
    Clipboard is a self-signed, un-notarized open-source beta.

    Auto-paste needs Accessibility permission:
      System Settings -> Privacy & Security -> Accessibility -> enable ClipboardApp.

    Updates are delivered through Homebrew:
      brew upgrade --cask clipboard
  EOS
end
```

Note: `auto_updates` is intentionally omitted. Homebrew's default is "no self-update", and `brew audit` flags `auto_updates false` as redundant. Omitting it satisfies the spec's "app does not self-update" intent.

- [ ] **Step 2: Create the tap CI workflow**

Create `packaging/homebrew/.github/workflows/audit.yml`:

```yaml
name: Audit cask

on:
  push:
  pull_request:

jobs:
  audit:
    runs-on: macos-14
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Homebrew
        uses: Homebrew/actions/setup-homebrew@master

      - name: Tap this repo
        run: brew tap anlostsheep/clipboard "$GITHUB_WORKSPACE"

      - name: brew style
        run: brew style anlostsheep/clipboard

      - name: brew audit
        run: brew audit --cask --tap anlostsheep/clipboard
```

- [ ] **Step 3: Create the tap README**

Create `packaging/homebrew/README.md`:

```markdown
# Clipboard Homebrew Tap (seed)

This directory is the seed content for the tap repo `anlostsheep/homebrew-clipboard`.
The tap repo is the authoritative home of the cask once bootstrapped (see
`docs/release-process.md`). `Scripts/publish-release.sh` rewrites the cask's
`version` and `sha256` in the tap clone on each release.

## Install

    brew tap anlostsheep/clipboard
    brew install --cask clipboard

Homebrew removes the quarantine attribute on cask install, so the app opens
without the Gatekeeper "unidentified developer" prompt even though the build is
self-signed and not notarized.

## Update

    brew upgrade --cask clipboard

## Uninstall

    brew uninstall --cask clipboard          # remove the app
    brew uninstall --cask --zap clipboard    # also remove local history + prefs
```

- [ ] **Step 4: Verify the cask is well-formed and rewritable**

Run:
```bash
tmp="$(mktemp -d)" && cp packaging/homebrew/Casks/clipboard.rb "$tmp/clipboard.rb" \
  && bash Scripts/update-cask.sh "$tmp/clipboard.rb" "9.9.9" "$(printf 'a%.0s' {1..64})" \
  && sed -nE 's/^[[:space:]]*(version|sha256) "([^"]*)".*/\1=\2/p' "$tmp/clipboard.rb" \
  && rm -rf "$tmp"
```
Expected: prints `version=9.9.9` and `sha256=aaaa...` (64 a's), proving the seed cask matches the stanza patterns `update-cask.sh` rewrites.

If `brew` is available, also run (optional, best-effort): `brew style packaging/homebrew/Casks/clipboard.rb`
Expected: no offenses (or auto-fixable formatting only; `brew style --fix` may be used).

- [ ] **Step 5: Commit**

```bash
git add packaging/homebrew/
git commit -m "build: add seed Homebrew cask, tap CI, and tap README"
```

---

### Task 3: `publish-release.sh` — release orchestrator (TDD on argument tier)

**Files:**
- Create: `Scripts/tests/test-publish-release-preconditions.sh`
- Create: `Scripts/publish-release.sh`

- [ ] **Step 1: Write the failing test**

Create `Scripts/tests/test-publish-release-preconditions.sh`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x Scripts/tests/test-publish-release-preconditions.sh && bash Scripts/tests/test-publish-release-preconditions.sh`
Expected: FAIL — script missing, so each invocation errors with "No such file or directory" rather than the expected needles; ends `TESTS FAILED`.

- [ ] **Step 3: Write minimal implementation**

Create `Scripts/publish-release.sh`:

```bash
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
cask_relpath="${CASK_RELPATH:-Casks/clipboard.rb}"

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

git diff --quiet && git diff --cached --quiet || die "git working tree is not clean; commit or stash first"

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
    brew install --cask clipboard

Update later with:

    brew upgrade --cask clipboard

Direct-download users: see docs/install.md for the first-open Gatekeeper steps.
EOF

gh release create "$tag" "$zip_path" "$sha_path" --title "$tag" --notes-file "$notes_file"

echo "==> updating cask in tap"
Scripts/update-cask.sh "$cask_file" "$version" "$sha256_value"
(
  cd "$tap_repo_dir"
  git add "$cask_relpath"
  git commit -m "clipboard $version"
  git push
)

echo
echo "==> done. verify with:"
echo "    brew update && brew upgrade --cask clipboard"
echo "    shasum -a 256 -c \"$sha_path\""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `chmod +x Scripts/publish-release.sh && bash Scripts/tests/test-publish-release-preconditions.sh`
Expected: PASS — `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Lint**

Run: `bash -n Scripts/publish-release.sh && { command -v shellcheck >/dev/null && shellcheck Scripts/publish-release.sh Scripts/tests/test-publish-release-preconditions.sh || echo "shellcheck not installed (optional)"; }`
Expected: no syntax errors; shellcheck clean or skip message.

> Coverage note (no silent caps): the test covers only the hermetic Tier-1 argument checks. The Tier-2 git/`gh`/network preconditions (clean tree, branch, existing tag, existing release) are verified by the Task 8 go-live dry run, not by automated tests, because hermetic git/`gh` fixtures add disproportionate complexity.

- [ ] **Step 6: Commit**

```bash
chmod +x Scripts/publish-release.sh Scripts/tests/test-publish-release-preconditions.sh
git add Scripts/publish-release.sh Scripts/tests/test-publish-release-preconditions.sh
git commit -m "build: add local one-command release publisher"
```

---

### Task 4: Docs — Homebrew-first install

**Files:**
- Modify: `docs/install.md`

- [ ] **Step 1: Prepend a Homebrew section**

In `docs/install.md`, immediately after the top intro paragraph (before `## 下载发布包`), insert:

```markdown
## 通过 Homebrew 安装(推荐)

```bash
brew tap anlostsheep/clipboard
brew install --cask clipboard
```

Homebrew 安装 cask 时会去掉 quarantine 属性,所以即使本构建是自签名、未公证,App 也能
直接打开,不会遇到"未识别开发者"的 Gatekeeper 拦截。

更新:

```bash
brew upgrade --cask clipboard
```

卸载:

```bash
brew uninstall --cask clipboard          # 仅移除 App
brew uninstall --cask --zap clipboard    # 同时移除本机历史与偏好
```

如果你不使用 Homebrew,可继续走下面的直接下载方式(首次打开仍需手动信任)。
```

- [ ] **Step 2: Verify**

Run: `grep -n "brew install --cask clipboard" docs/install.md`
Expected: at least one match in the new section.

- [ ] **Step 3: Commit**

```bash
git add docs/install.md
git commit -m "docs: lead install with Homebrew cask"
```

---

### Task 5: Docs — release process via `publish-release.sh`

**Files:**
- Modify: `docs/release-process.md`

- [ ] **Step 1: Add the one-command publish + tap maintenance sections**

In `docs/release-process.md`, after the existing `## 构建发布包` section, insert:

```markdown
## 一键发布(publish-release.sh)

设置 tap 仓库本地克隆路径,然后用一条命令完成"构建 → 打包 → 发版 → 回写 cask":

```bash
git clone https://github.com/anlostsheep/homebrew-clipboard.git ../homebrew-clipboard

TAP_REPO_DIR="$PWD/../homebrew-clipboard" \
VERSION=0.2.0 \
Scripts/publish-release.sh
```

脚本会:

- 校验前置条件(版本号、在 master、工作树干净、tag 不存在、gh 已登录、tap 可达、GitHub
  release 不存在)。
- 以 `REQUIRE_STABLE_CODE_SIGNING=1` 调 `Scripts/package-release.sh` 产出稳定签名的 zip
  和 `.sha256`。
- 打并推 git tag `vX.Y.Z`。
- 用 `gh release create` 上传 zip + `.sha256` + release notes。
- 调 `Scripts/update-cask.sh` 把新 `version`/`sha256` 写进 tap 的 `Casks/clipboard.rb`,
  并在 tap 仓库提交、推送。

构建与稳定签名全程在本地完成;只有 `gh` 发布动作触网。App 自身不引入任何网络调用。

## Homebrew Tap 维护

tap 仓库 `anlostsheep/homebrew-clipboard` 的初始内容来自本仓库的 `packaging/homebrew/`。
首次 bootstrap 见 `docs/superpowers/plans/2026-06-24-distribution-trust-chain-homebrew.md`
的 go-live 步骤。bootstrap 之后,tap 仓库是 cask 的权威来源,`publish-release.sh` 每次发版
原子地回写它的 `version` 与 `sha256`。tap 仓库的 CI(`.github/workflows/audit.yml`)对
cask 跑 `brew style` 与 `brew audit`。
```

- [ ] **Step 2: Verify**

Run: `grep -n "publish-release.sh" docs/release-process.md`
Expected: matches in the new section.

- [ ] **Step 3: Commit**

```bash
git add docs/release-process.md
git commit -m "docs: document one-command publish and tap maintenance"
```

---

### Task 6: Docs — README install + acceptance checklist

**Files:**
- Modify: `README.md`
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Lead the README install section with Homebrew**

In `README.md`, replace the heading line `## 从发布包安装` and insert a Homebrew block before it so the section reads:

```markdown
## 安装

推荐使用 Homebrew:

```bash
brew tap anlostsheep/clipboard
brew install --cask clipboard
```

Homebrew 安装 cask 时会去掉 quarantine 属性,App 直接打开,不会遇到 Gatekeeper 首次打开
拦截(尽管本构建是自签名、未公证)。更新用 `brew upgrade --cask clipboard`。

不使用 Homebrew 时,也可以从发布包安装。

## 从发布包安装
```

(Keep the existing "从发布包安装" body that follows unchanged.)

- [ ] **Step 2: Verify README**

Run: `grep -n "brew install --cask clipboard" README.md`
Expected: at least one match.

- [ ] **Step 3: Append distribution acceptance items**

Append to `docs/manual-acceptance-checklist.md`:

```markdown
## 分发信任链(Homebrew 免费路)— 2026-06-24

- [ ] 全新 Homebrew 安装:`brew tap anlostsheep/clipboard && brew install --cask clipboard` 成功。
- [ ] Homebrew 安装后 App 打开无需 Gatekeeper 右键 Open 步骤。
- [ ] `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` 无输出。
- [ ] 授予辅助功能权限后自动粘贴可用。
- [ ] `brew upgrade --cask clipboard` 从版本 N 升到 N+1。
- [ ] 辅助功能权限在 Homebrew 升级后仍保持(稳定签名守住)。
- [ ] `brew uninstall --cask --zap clipboard` 移除 App 及本机数据目录。
- [ ] 直接下载 zip 路径在文档化的 Gatekeeper 绕过步骤下仍可用。
```

- [ ] **Step 4: Verify checklist**

Run: `grep -n "分发信任链(Homebrew 免费路)" docs/manual-acceptance-checklist.md`
Expected: one match.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/manual-acceptance-checklist.md
git commit -m "docs: lead README install with Homebrew and add acceptance items"
```

---

### Task 7: Repo-wide verification gate

**Files:** none (verification only)

- [ ] **Step 1: Run the existing main gate**

Run: `Scripts/verify.sh`
Expected: PASS (the distribution change touches scripts/docs only and must not regress the Swift gate).

- [ ] **Step 2: Run the new shell tests together**

Run: `bash Scripts/tests/test-update-cask.sh && bash Scripts/tests/test-publish-release-preconditions.sh`
Expected: both end with `ALL TESTS PASSED`.

- [ ] **Step 3: Whitespace check**

Run: `git diff --check HEAD~6`
Expected: no whitespace errors across this plan's commits.

---

### Task 8: Go-live (maintainer-operated — requires authorization)

> **Do not auto-execute.** These steps create a public GitHub repo and publish a real release — outward-facing and hard to reverse. They require the maintainer's GitHub account and a real version number. An executing agent must stop and hand this to the user.

- [ ] **Step 1: Create and seed the tap repo**

```bash
gh repo create anlostsheep/homebrew-clipboard --public \
  --description "Homebrew tap for Clipboard"

tap="../homebrew-clipboard"
git clone https://github.com/anlostsheep/homebrew-clipboard.git "$tap"
mkdir -p "$tap/Casks" "$tap/.github/workflows"
cp packaging/homebrew/Casks/clipboard.rb "$tap/Casks/clipboard.rb"
cp packaging/homebrew/.github/workflows/audit.yml "$tap/.github/workflows/audit.yml"
cp packaging/homebrew/README.md "$tap/README.md"
( cd "$tap" && git add . && git commit -m "Seed clipboard cask" && git push )
```

- [ ] **Step 2: Confirm tap CI is green**

Check the tap repo's Actions tab: the `Audit cask` workflow (`brew style` + `brew audit`) passes. Fix any `brew style` offenses with `brew style --fix Casks/clipboard.rb` in the tap and push.

- [ ] **Step 3: Publish the first real release**

```bash
TAP_REPO_DIR="$PWD/../homebrew-clipboard" VERSION=0.2.0 Scripts/publish-release.sh
```
Expected: a GitHub Release `v0.2.0` with the zip + `.sha256`, and a tap commit `clipboard 0.2.0` whose cask `sha256` matches the released asset.

- [ ] **Step 4: End-to-end install verification (ideally a clean user / second Mac)**

```bash
brew update
brew install --cask clipboard
open -a ClipboardApp                                        # opens with no right-click step
xattr -p com.apple.quarantine /Applications/ClipboardApp.app   # expected: no output
shasum -a 256 -c dist/ClipboardApp-v0.2.0-macos.zip.sha256     # expected: OK
```
Grant Accessibility permission and confirm auto-paste works.

- [ ] **Step 5: Upgrade + zap verification (after a later release exists)**

```bash
brew upgrade --cask clipboard          # N -> N+1, Accessibility permission persists
brew uninstall --cask --zap clipboard  # removes app + ~/Library/Application Support/com.local.clipboard-manager
```

- [ ] **Step 6: Record acceptance**

Check off the items added in Task 6 under "分发信任链(Homebrew 免费路)— 2026-06-24" as each is physically confirmed, and append a dated acceptance record. Commit:

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record Homebrew distribution acceptance"
```

---

## Self-Review

**Spec coverage** (against `2026-06-24-distribution-trust-chain-homebrew-design.md`):
- Homebrew Cask in a dedicated tap → Task 2 (seed) + Task 8 (tap repo). ✔
- `publish-release.sh` local pipeline preserving stable signing → Task 3. ✔
- Version single source of truth (git tag → Info.plist/asset/cask) → Task 3 (`publish-release.sh` owns VERSION, creates tag; build already writes Info.plist). ✔
- Cask stanzas (url/app/depends_on/zap/caveats; quarantine auto-stripped) → Task 2. ✔ (`auto_updates` deliberately omitted; rationale in Task 2.)
- Docs lead with Homebrew, retain direct download → Tasks 4, 5, 6. ✔
- Manual acceptance items → Task 6 + Task 8. ✔
- Tap CI (`brew audit` + `brew style`) → Task 2. ✔
- Zero in-app network calls → no app code touched anywhere in this plan. ✔
- Error handling / abort modes → encoded in `publish-release.sh` Tier 1/2; local artifacts complete before remote push. ✔

**Placeholder scan:** Full file contents and exact commands given for every create/modify step; no TBD/TODO. The cask's `sha256 "0000...0000"` is an intentional seed value rewritten at release time, not a plan placeholder.

**Type/name consistency:** `Scripts/update-cask.sh` signature `<cask-file> <version> <sha256>` is identical in its test (Task 1), its seed-cask verification (Task 2), and its caller (`publish-release.sh`, Task 3). Env var names `VERSION`, `TAP_REPO_DIR`, `REQUIRE_STABLE_CODE_SIGNING`, `CASK_RELPATH` are consistent across Task 3 and Tasks 5/8. Cask token `clipboard`, tap `anlostsheep/clipboard`, asset name `ClipboardApp-v${version}-macos.zip`, and bundle id `com.local.clipboard-manager` are consistent across cask, scripts, docs, and zap.
