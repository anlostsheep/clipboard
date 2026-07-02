# Clipboard 分发 go-live 收尾(去 gh · curl+PAT 发布)实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾 `clipboardapp` 改名、把 `publish-release.sh` 从 `gh` 迁到 `curl`+PAT(keychain),并完成引导式 go-live —— 发布稳定签名的 v0.1.0,让 `brew install --cask clipboardapp` 跑通。

**Architecture:** 主仓库本地稳定签名构建 + 打包不变;唯一代码改动是 `publish-release.sh` 的发布段从 `gh` CLI 迁移到 `curl` 调 GitHub REST API,PAT 从 macOS keychain 读取。tap 仓库用新 token `clipboardapp` re-seed 消除 homebrew-core 冲突。go-live 的推送 / re-seed / 发布由维护者在场逐步执行,发布前明确确认。

**Tech Stack:** Bash、curl、jq、GitHub REST API、macOS `security`(keychain)、Homebrew Cask、既有 SwiftPM 构建/签名脚本。

**Reference spec:** `docs/superpowers/specs/2026-07-02-clipboard-go-live-pat-publish-design.md`

---

## File Structure

修改(本仓库):
- `Scripts/tests/test-update-cask.sh` — 测试 fixture 里残留的 `clipboard` token 改为 `clipboardapp`(仅一致性,行为不变)。
- `Scripts/publish-release.sh` — 发布段从 `gh` 迁移到 `curl`+PAT(keychain);Tier-1 参数校验保持最前不变。
- `docs/release-process.md` — 前置条件与发布方式描述从"gh 已登录 / gh release create"改为 PAT(keychain)+ curl REST;补半发布恢复说明。
- `docs/manual-acceptance-checklist.md` — go-live 后勾选"分发信任链"条目并追加日期化验收记录(Task 9)。

工作区已有(尚未提交)的改名改动一并在 Task 1 提交:
- `README.md`、`docs/install.md`、`docs/release-process.md`、`docs/manual-acceptance-checklist.md`、`packaging/homebrew/README.md`、新增 `packaging/homebrew/Casks/clipboardapp.rb`、删除 `packaging/homebrew/Casks/clipboard.rb`、`Scripts/publish-release.sh` 中的 token 引用。

仓库外(操作性,Task 5/7/8):推 master、用 `clipboardapp` re-seed tap 仓库 `anlostsheep/homebrew-clipboard`、发布第一个真实 release。

**Scope note:** 不改 `build-app-bundle.sh` / `package-release.sh`(签名与打包已验证可用)。不动 tap 仓库的 `.github/workflows/audit.yml`(该 workflow 已修好,唯一残留失败是 token 冲突,由 Task 7 换 token 解决)。

---

### Task 1: 收尾 clipboardapp 改名并提交

**Files:**
- Modify: `Scripts/tests/test-update-cask.sh:21,25,60`

- [ ] **Step 1: 改 fixture 里的 token**

`Scripts/tests/test-update-cask.sh` 第 21 行:

```bash
cask="$work/clipboardapp.rb"
```

第 25 行与第 60 行(两处 `make_cask` heredoc 里的首行)都从 `cask "clipboard" do` 改为:

```ruby
cask "clipboardapp" do
```

(该测试只验证 `update-cask.sh` 改写 `version`/`sha256`,与 token 无关;改名仅为仓库一致性。)

- [ ] **Step 2: 跑测试确认仍通过**

Run: `bash Scripts/tests/test-update-cask.sh`
Expected: 末行 `ALL TESTS PASSED`,退出 0。

- [ ] **Step 3: 确认工作区改动范围**

Run: `git status -s`
Expected: 包含 `README.md`、`Scripts/publish-release.sh`、`Scripts/tests/test-update-cask.sh`、`docs/install.md`、`docs/manual-acceptance-checklist.md`、`docs/release-process.md`、`packaging/homebrew/README.md` 的修改,`packaging/homebrew/Casks/clipboard.rb` 删除,`packaging/homebrew/Casks/clipboardapp.rb` 新增。无其它无关文件。

- [ ] **Step 4: 提交改名**

```bash
git add README.md Scripts/publish-release.sh Scripts/tests/test-update-cask.sh \
  docs/install.md docs/manual-acceptance-checklist.md docs/release-process.md \
  packaging/homebrew/README.md packaging/homebrew/Casks/clipboardapp.rb packaging/homebrew/Casks/clipboard.rb
git commit -m "build: rename cask token to clipboardapp to avoid homebrew-core conflict"
```

Run: `git status -s`
Expected: 干净(无未提交改动)。

---

### Task 2: 本地绿色门禁

**Files:** 无(仅验证)

- [ ] **Step 1: 主门禁**

Run: `Scripts/verify.sh`
Expected: 通过(swift test + swift build + test-automation 全绿,退出 0)。

- [ ] **Step 2: shell 测试**

Run: `bash Scripts/tests/test-update-cask.sh && bash Scripts/tests/test-publish-release-preconditions.sh`
Expected: 两个都以 `ALL TESTS PASSED` 结束。

- [ ] **Step 3: cask 静态检查**

Run: `brew style packaging/homebrew/Casks/clipboardapp.rb`
Expected: `no offenses detected`。

- [ ] **Step 4: 空白检查**

Run: `git diff --check HEAD~1`
Expected: 无空白错误。

---

### Task 3: 把 publish-release.sh 从 gh 迁移到 curl+PAT

**Files:**
- Modify: `Scripts/publish-release.sh`(整体替换为下面的内容)

- [ ] **Step 1: 用下面完整内容覆盖 `Scripts/publish-release.sh`**

```bash
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

This build is self-signed and not notarized. Recommended install (no Gatekeeper
prompt) is via Homebrew:

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
```

- [ ] **Step 2: 语法与 lint**

Run: `bash -n Scripts/publish-release.sh && { command -v shellcheck >/dev/null && shellcheck Scripts/publish-release.sh || echo "shellcheck not installed (optional)"; }`
Expected: 无语法错误;shellcheck 干净或跳过提示。

- [ ] **Step 3: 确认 Tier-1 参数测试仍通过(证明 hermetic 未被破坏)**

Run: `bash Scripts/tests/test-publish-release-preconditions.sh`
Expected: `ALL TESTS PASSED`。三个用例(缺 VERSION / 坏 semver / 缺 TAP_REPO_DIR)都在 Tier-1 中止,不触发 keychain/curl/git。

> Coverage note(no silent caps):自动化只覆盖 Tier-1 参数校验。Tier-2 的 PAT 读取、仓库可达、release 存在性预检,以及创建 release + 上传资产的 curl 路径,由 Task 8 的首次真实发布验证 —— hermetic 地 mock GitHub API 的成本与本轮不成比例。缓解已内建:构建/打 tag 之前先做 token+仓库+release fail-fast 预检;本地产物齐备后才做远端推送。

- [ ] **Step 4: 提交**

```bash
git add Scripts/publish-release.sh
git commit -m "build: publish releases via GitHub REST API + keychain PAT (drop gh)"
```

---

### Task 4: 更新 release-process.md 的发布方式与恢复说明

**Files:**
- Modify: `docs/release-process.md:70,75,79`(以及在发布段末尾补恢复说明)

- [ ] **Step 1: 改前置条件那一行**

把(第 70-71 行):

```markdown
- 校验前置条件(版本号、在 master、工作树干净、tag 不存在、gh 已登录、tap 可达、GitHub
  release 不存在)。
```

改为:

```markdown
- 校验前置条件(版本号、在 master、工作树干净、tag 不存在、tap 可达、GitHub release 不存在,
  以及 keychain 中的 GitHub PAT 能访问仓库)。
```

- [ ] **Step 2: 改发布方式那一行**

把(第 75 行):

```markdown
- 用 `gh release create` 上传 zip + `.sha256` + release notes。
```

改为:

```markdown
- 用 GitHub REST API(curl + macOS keychain 中的 PAT)创建 release 并上传 zip + `.sha256`
  + release notes;PAT 全程不打印、不进 URL。
```

- [ ] **Step 3: 改触网表述那一行**

把(第 79 行):

```markdown
构建与稳定签名全程在本地完成;只有 `gh` 发布动作触网。App 自身不引入任何网络调用。
```

改为:

```markdown
构建与稳定签名全程在本地完成;只有发布动作(curl 调 GitHub REST API)触网。App 自身不引入
任何网络调用。发布脚本无需安装 `gh`。
```

- [ ] **Step 4: 在 "## 一键发布" 段末尾(第 79 行之后、"## Homebrew Tap 维护" 之前)补恢复说明**

插入:

```markdown

发布失败恢复:若打 tag 之后、发布未完成(如 release 已建但资产上传失败),脚本会在该步中止。
恢复方式是先清掉半成品,再重跑:

```bash
git push origin ":refs/tags/vX.Y.Z" && git tag -d "vX.Y.Z"   # 删除远端与本地 tag
# 在 GitHub 上删除该 tag 对应的半成品 release
```
```

- [ ] **Step 5: 校验**

Run: `grep -n "GitHub REST API" docs/release-process.md; grep -c "gh release create" docs/release-process.md`
Expected: REST API 说明有匹配;`gh release create` 计数为 `0`。

- [ ] **Step 6: 提交**

```bash
git add docs/release-process.md
git commit -m "docs: describe PAT/curl publish and release recovery"
```

---

### Task 5: 推送主仓库(维护者确认后)

> **需维护者确认**:这是把 14+ 个 commit 首次公开到 `origin`。

**Files:** 无

- [ ] **Step 1: 确认 repo 为 public**

在 GitHub 上确认 `anlostsheep/clipboard` 是 public(cask 的 `url` 指向其 release 资产,私有会导致安装失败)。若为私有,维护者在 GitHub 设为 public。

- [ ] **Step 2: 推送**

Run: `git push origin master`
Expected: 推送成功。

- [ ] **Step 3: 校验**

Run: `git status -sb | head -1`
Expected: `## master...origin/master`(无 ahead)。

---

### Task 6: 校验 keychain PAT 可访问仓库(fail-fast,无需 gh)

**Files:** 无

- [ ] **Step 1: 读 PAT 并探仓库(不打印 token)**

Run:
```bash
tok="$(security find-internet-password -s github.com -a anlostsheep -w 2>/dev/null || true)"
[[ -n "$tok" ]] || { echo "no PAT in keychain"; exit 1; }
curl -sS -o /dev/null -w 'repo access HTTP %{http_code}\n' \
  -H "Authorization: Bearer $tok" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/anlostsheep/clipboard
unset tok
```
Expected: `repo access HTTP 200`。若非 200,先修 PAT(有效性/scope,需要 `repo` 或 fine-grained `contents:write`)再往下。

---

### Task 7: 用 clipboardapp re-seed tap(维护者确认后)

> **需维护者确认**:向公开 tap 仓库推送。

**Files:**(tap 仓库,非本仓库)
- tap `Casks/clipboardapp.rb`(新增,来自本仓库 seed)
- tap `Casks/clipboard.rb`(删除)
- tap `README.md`(同步本仓库 seed 的 token 更新)

- [ ] **Step 1: 准备 tap 本地克隆**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
if [[ -d "$tap/.git" ]]; then ( cd "$tap" && git pull --ff-only ); \
else git clone https://github.com/anlostsheep/homebrew-clipboard.git "$tap"; fi
ls "$tap/Casks"
```
Expected: tap 克隆就绪;`Casks/` 当前含旧的 `clipboard.rb`。

- [ ] **Step 2: 换 cask 与 README(不动 .github/workflows)**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
cp packaging/homebrew/Casks/clipboardapp.rb "$tap/Casks/clipboardapp.rb"
cp packaging/homebrew/README.md "$tap/README.md"
( cd "$tap" && git rm -q Casks/clipboard.rb )
( cd "$tap" && git status -s )
```
Expected:tap 里 `Casks/clipboardapp.rb` 新增、`Casks/clipboard.rb` 删除、`README.md` 修改;`.github/workflows/audit.yml` 不变(该 workflow 已修好,残留失败只是 token 冲突)。

- [ ] **Step 3: 本地静态检查(可选,brew 可用时)**

Run: `brew style "$PWD/../homebrew-clipboard/Casks/clipboardapp.rb"`
Expected: `no offenses detected`。

- [ ] **Step 4: 提交并推送 tap**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
( cd "$tap" && git add Casks/clipboardapp.rb README.md && git commit -m "Rename cask token to clipboardapp" && git push )
```
Expected: 推送成功。

- [ ] **Step 5: 确认 tap CI 变绿**

在 tap 仓库 Actions 看 `Audit cask` 工作流(`brew style` + `brew audit`)通过 —— 这是 token 冲突消除的权威确认。若 `brew audit` 仍报某类问题,按其提示修 tap 里的 cask 后再推。

---

### Task 8: 发布 v0.1.0(维护者授权后执行,不可逆)

> **需维护者明确授权**:创建公开 GitHub Release 并推送 tap cask,难以撤销。执行前确认 Task 1-7 全绿。

**Files:** 无(脚本产出 release + 回写 tap)

- [ ] **Step 1: 一键发布**

Run:
```bash
TAP_REPO_DIR="$PWD/../homebrew-clipboard" VERSION=0.1.0 Scripts/publish-release.sh
```
Expected(脚本内部顺序):Tier-1/2 预检通过 → package-release(verify + 稳定签名构建 + zip + sha)→ 打并推 tag `v0.1.0` → curl 创建 GitHub release → 上传 zip 与 `.sha256`(各 HTTP 201)→ `update-cask.sh` 回写 tap cask → tap 提交 `clipboardapp 0.1.0` 并推送 → 打印验证提示。

- [ ] **Step 2: 校验发布产物**

Run:
```bash
tok="$(security find-internet-password -s github.com -a anlostsheep -w)"
curl -sS -H "Authorization: Bearer $tok" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/anlostsheep/clipboard/releases/tags/v0.1.0 \
  | jq -r '.tag_name, (.assets[].name)'
unset tok
```
Expected:输出 `v0.1.0`、`ClipboardApp-v0.1.0-macos.zip`、`ClipboardApp-v0.1.0-macos.zip.sha256`。

- [ ] **Step 3: 校验 tap cask 已回写且 sha 一致**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
( cd "$tap" && git pull --ff-only && sed -nE 's/^[[:space:]]*(version|sha256) "([^"]*)".*/\1=\2/p' Casks/clipboardapp.rb )
awk '{print "asset sha256="$1}' dist/ClipboardApp-v0.1.0-macos.zip.sha256
```
Expected:cask 的 `version=0.1.0`,`sha256=<64hex>` 与 asset sha256 完全一致。

- [ ] **Step 4: 校验签名 Authority**

Run: `codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app 2>&1 | grep Authority`
Expected: `Authority=ClipboardApp Local Code Signing`。

---

### Task 9: E2E 验收并记录

> 主要由维护者在真实 macOS 上操作(本机 macOS 26 满足 `depends_on macos: >= sonoma`;理想是干净环境/第二台机)。

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`(勾选"分发信任链"条目并追加日期化记录)

- [ ] **Step 1: 全新安装**

Run:
```bash
brew update
brew tap anlostsheep/clipboard
brew install --cask clipboardapp
```
Expected: 安装成功。

- [ ] **Step 2: 打开无 Gatekeeper 拦截 + quarantine 无残留**

Run:
```bash
open -a ClipboardApp
xattr -p com.apple.quarantine /Applications/ClipboardApp.app 2>&1
```
Expected: App 直接打开(无右键 Open 步骤);`xattr` 无输出(属性不存在)。

- [ ] **Step 3: 校验和 + 自动粘贴**

Run: `shasum -a 256 -c dist/ClipboardApp-v0.1.0-macos.zip.sha256`
Expected: `OK`。
手动:系统设置授予辅助功能权限后,确认自动粘贴可用。

- [ ] **Step 4: 勾选验收清单并追加记录**

在 `docs/manual-acceptance-checklist.md` 的"分发信任链(Homebrew 免费路)"分区把已物理确认的条目从 `- [ ]` 改为 `- [x]`,并在该分区末尾追加一行日期化记录:

```markdown
- 验收记录 2026-07-02:v0.1.0 经 `brew install --cask clipboardapp` 全新安装通过,打开无 Gatekeeper 拦截,quarantine 无残留,sha256 校验 OK,辅助功能授权后自动粘贴可用。
```

(`brew upgrade` 与 `--zap` 两条待有后续版本 / 卸载时再验证,暂留 `- [ ]`。)

- [ ] **Step 5: 提交**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record v0.1.0 Homebrew distribution acceptance"
git push origin master
```

---

## Self-Review

**Spec coverage**(对照 `2026-07-02-clipboard-go-live-pat-publish-design.md`):
- clipboardapp 改名收尾(含 fixture)→ Task 1。✔
- 本地绿色门禁 → Task 2。✔
- publish-release.sh 去 gh、curl+PAT(keychain)、REST 发布、fail-fast 预检、Tier-1 不破 → Task 3。✔
- release-process.md 反映 PAT/curl + 半发布恢复 → Task 4。✔
- 推 master / repo public → Task 5。✔
- PAT 可达 fail-fast(无需 gh)→ Task 6 + Task 3 内建。✔
- 用 clipboardapp re-seed tap、CI 绿 → Task 7。✔
- 发布 v0.1.0、稳定签名、回写 tap、sha 一致 → Task 8。✔
- E2E(无 Gatekeeper、quarantine 无残留、自动粘贴、sha)+ 验收记录 → Task 9。✔
- 无应用内网络调用;notarize/Sparkle/App Store/bundle-id 保持范围外 → 全程未碰 App 代码。✔

**Placeholder scan:** 每个改代码步骤都给了完整内容;curl 覆盖边界已在 Task 3 coverage note 明示,非占位。cask 的 `0000…` seed sha 为设计内的 bootstrap 值。

**Type/name consistency:** cask token `clipboardapp`、tap 名 `anlostsheep/clipboard`、owner/repo `anlostsheep/clipboard`、keychain account `anlostsheep`、资产名 `ClipboardApp-v${version}-macos.zip`、`CASK_RELPATH=Casks/clipboardapp.rb`、`update-cask.sh <cask> <version> <sha256>` 签名,在脚本、文档、tap、验收步骤间一致。`package-release.sh` 的 `release package:` / `checksum:` 输出与 `publish-release.sh` 的 sed 解析吻合。
