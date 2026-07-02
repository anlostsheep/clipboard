# Clipboard Gatekeeper quarantine postflight 修订实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `brew install --cask clipboardapp` 装完的 App 首次打开无 Gatekeeper 拦截 —— 通过 cask postflight 在安装/升级后移除 quarantine,并把所有"Homebrew 自动去 quarantine"的错误文档改为准确的 postflight 机制 + 透明披露。

**Architecture:** 纯 cask + 文档改动,不改 App 代码、不发新 release、无网络。seed cask 加 postflight(去 quarantine)与透明 caveats;LIVE tap cask 从更新后的 seed + 真实 sha 用 `update-cask.sh` 重生成,保持与 seed 同步且 stanza 顺序正确。已实测:该 postflight 过 `brew style` + `brew audit`,且手动去 quarantine 可消除首开拦截。

**Tech Stack:** Homebrew Cask(Ruby DSL)、`brew style`/`brew audit`、`xattr`、既有 `Scripts/update-cask.sh`、curl+PAT 发布脚本。

**Reference spec:** `docs/superpowers/specs/2026-07-02-clipboard-gatekeeper-quarantine-postflight-design.md`

---

## File Structure

修改(本仓库,Task 1-3):
- `packaging/homebrew/Casks/clipboardapp.rb` — seed cask 加 postflight(去 quarantine)+ 透明 caveats。
- `README.md`、`docs/install.md`、`packaging/homebrew/README.md` — 把"Homebrew 去 quarantine"改为"cask postflight 去 quarantine"+ 透明披露。
- `Scripts/publish-release.sh` — release notes 文案改为准确表述(cask 去 quarantine)。

仓库外(操作,Task 5-6):LIVE tap `anlostsheep/homebrew-clipboard` 的 `Casks/clipboardapp.rb` 与 `README.md` 更新并推送;真机 E2E 复验;验收记录回写。

**Scope note:** 不发新 app release、不改 App 代码、不引入网络。版本保持 `0.1.0`(纯 cask 改动)。

**Branch:** Task 1-3 在 feature 分支 `fix/gatekeeper-quarantine-postflight` 上进行,Task 4 合回 master 并推;Task 5-6 为 tap/真机操作。开始 Task 1 前先建分支:

```bash
git checkout -b fix/gatekeeper-quarantine-postflight
```

---

### Task 1: seed cask 加 postflight + 透明 caveats

**Files:**
- Modify: `packaging/homebrew/Casks/clipboardapp.rb`

- [ ] **Step 1: 在 `app` 之后插入 postflight**

把:

```ruby
  app "ClipboardApp.app"

  zap trash: [
```

改为(postflight 置于 `app` 与 `zap` 之间,符合 Homebrew stanza 顺序 app → postflight → zap → caveats):

```ruby
  app "ClipboardApp.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-d", "-r", "com.apple.quarantine", "#{appdir}/ClipboardApp.app"]
  end

  zap trash: [
```

- [ ] **Step 2: 更新 caveats 加透明披露**

把:

```ruby
  caveats <<~EOS
    Clipboard is a self-signed, un-notarized open-source beta.

    Auto-paste needs Accessibility permission:
      System Settings -> Privacy & Security -> Accessibility -> enable ClipboardApp.

    Updates are delivered through Homebrew:
      brew upgrade --cask clipboardapp
  EOS
```

改为:

```ruby
  caveats <<~EOS
    Clipboard is a self-signed, un-notarized open-source beta.

    This cask removes the macOS quarantine attribute after install so the app
    opens without a Gatekeeper prompt. That bypasses Gatekeeper's check for this
    app -- you are trusting this tap by installing it.

    Auto-paste needs Accessibility permission:
      System Settings -> Privacy & Security -> Accessibility -> enable ClipboardApp.

    Updates are delivered through Homebrew:
      brew upgrade --cask clipboardapp
  EOS
```

- [ ] **Step 3: brew style 确认(含 stanza 顺序)**

Run: `brew style packaging/homebrew/Casks/clipboardapp.rb`
Expected: `1 file inspected, no offenses detected`。若报 `StanzaOrder`,运行 `brew style --fix packaging/homebrew/Casks/clipboardapp.rb` 后再跑一次至无 offense。

- [ ] **Step 4: 确认 update-cask.sh 仍能改写(postflight 不受影响)**

Run:
```bash
tmp="$(mktemp -d)"; cp packaging/homebrew/Casks/clipboardapp.rb "$tmp/c.rb"
bash Scripts/update-cask.sh "$tmp/c.rb" "9.9.9" "$(printf 'a%.0s' {1..64})" >/dev/null
sed -nE 's/^[[:space:]]*(version|sha256) "([^"]*)".*/\1=\2/p' "$tmp/c.rb"
grep -c "postflight do" "$tmp/c.rb"; rm -rf "$tmp"
```
Expected: 打印 `version=9.9.9`、`sha256=aaaa…`(64 个 a),`postflight do` 计数为 `1`(证明改写只动 version/sha,postflight 保留)。

- [ ] **Step 5: 提交**

```bash
git add packaging/homebrew/Casks/clipboardapp.rb
git commit -m "build: strip quarantine via cask postflight, disclose in caveats"
```

---

### Task 2: 修正文档里"Homebrew 去 quarantine"的错误表述

**Files:**
- Modify: `docs/install.md:12-13`
- Modify: `README.md:46-47`
- Modify: `packaging/homebrew/README.md:13-15`

- [ ] **Step 1: docs/install.md**

把:

```markdown
Homebrew 安装 cask 时会去掉 quarantine 属性,所以即使本构建是自签名、未公证,App 也能
直接打开,不会遇到"未识别开发者"的 Gatekeeper 拦截。
```

改为:

```markdown
本 cask 在安装后通过 postflight 移除 quarantine 属性,所以即使本构建是自签名、未公证,App
也能直接打开,不会遇到"未识别开发者"的 Gatekeeper 拦截。这相当于替你自动完成首次打开的手动
信任(即绕过 Gatekeeper 对该 App 的这层校验),前提是你信任本 tap。
```

- [ ] **Step 2: README.md**

把:

```markdown
Homebrew 安装 cask 时会去掉 quarantine 属性,App 直接打开,不会遇到 Gatekeeper 首次打开
拦截(尽管本构建是自签名、未公证)。更新用 `brew upgrade --cask clipboardapp`。
```

改为:

```markdown
本 cask 在安装后通过 postflight 移除 quarantine 属性,App 直接打开,不会遇到 Gatekeeper
首次打开拦截(尽管本构建是自签名、未公证)。这会绕过 Gatekeeper 对该 App 的校验,前提是你
信任本 tap。更新用 `brew upgrade --cask clipboardapp`。
```

- [ ] **Step 3: packaging/homebrew/README.md**

把:

```markdown
Homebrew removes the quarantine attribute on cask install, so the app opens
without the Gatekeeper "unidentified developer" prompt even though the build is
self-signed and not notarized.
```

改为:

```markdown
The cask's postflight removes the quarantine attribute after install, so the app
opens without the Gatekeeper "unidentified developer" prompt even though the build
is self-signed and not notarized. This bypasses Gatekeeper's check for this app --
you are trusting this tap when you install it.
```

- [ ] **Step 4: 校验**

Run: `grep -rn "会去掉 quarantine\|removes the quarantine attribute on cask install" README.md docs/install.md packaging/homebrew/README.md`
Expected: 无匹配(错误表述已全部替换)。

- [ ] **Step 5: 提交**

```bash
git add README.md docs/install.md packaging/homebrew/README.md
git commit -m "docs: correct quarantine mechanism to cask postflight, disclose tradeoff"
```

---

### Task 3: 修正 publish-release.sh 的 release notes 文案

**Files:**
- Modify: `Scripts/publish-release.sh`

- [ ] **Step 1: 改 release notes 里暗示"Homebrew 免 Gatekeeper"的措辞**

把:

```bash
This build is self-signed and not notarized. Recommended install (no Gatekeeper
prompt) is via Homebrew:
```

改为:

```bash
This build is self-signed and not notarized. Recommended install is via Homebrew;
the cask removes the quarantine attribute after install so the app opens without a
Gatekeeper prompt:
```

- [ ] **Step 2: 语法 + lint**

Run: `bash -n Scripts/publish-release.sh && { command -v shellcheck >/dev/null && shellcheck Scripts/publish-release.sh || echo "shellcheck not installed (optional)"; }`
Expected: 无语法错误;shellcheck 干净或跳过提示。

- [ ] **Step 3: Tier-1 参数测试仍通过**

Run: `bash Scripts/tests/test-publish-release-preconditions.sh`
Expected: `ALL TESTS PASSED`。

- [ ] **Step 4: 提交**

```bash
git add Scripts/publish-release.sh
git commit -m "docs: correct release-notes template to cask-postflight quarantine removal"
```

---

### Task 4: 合并 feature 分支回 master 并推送

**Files:** 无

- [ ] **Step 1: 合并(ff-only)**

Run:
```bash
git checkout master
git merge --ff-only fix/gatekeeper-quarantine-postflight
git log --oneline -3
```
Expected: fast-forward,master 顶端为 Task 3 的提交。

- [ ] **Step 2: 推送**

Run: `git push origin master`
Expected: 推送成功。

- [ ] **Step 3: 校验**

Run: `git status -sb | head -1`
Expected: `## master...origin/master`(无 ahead)。

---

### Task 5: 更新 LIVE tap cask(从 seed 重生成)+ tap README,推送并确认 CI 绿

> **需维护者确认**:向公开 tap 仓库推送。

**Files:**(tap 仓库,非本仓库)
- tap `Casks/clipboardapp.rb`(从更新后的 seed + 真实 sha 重生成)
- tap `README.md`(同步更新后的 seed README)

- [ ] **Step 1: 从 seed 重生成 tap cask(带 postflight)+ 回填真实 version/sha**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
( cd "$tap" && git pull --ff-only )
sha="$(awk '{print $1}' dist/ClipboardApp-v0.1.0-macos.zip.sha256)"
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "no local sha; deriving from release"; sha="$(curl -sSL https://github.com/anlostsheep/clipboard/releases/download/v0.1.0/ClipboardApp-v0.1.0-macos.zip.sha256 | awk '{print $1}')"; }
cp packaging/homebrew/Casks/clipboardapp.rb "$tap/Casks/clipboardapp.rb"
bash Scripts/update-cask.sh "$tap/Casks/clipboardapp.rb" "0.1.0" "$sha"
cp packaging/homebrew/README.md "$tap/README.md"
```
Expected: `update-cask.sh` 打印 `updated ... -> version 0.1.0, sha256 <sha>`。

- [ ] **Step 2: 确认 tap cask 正确(postflight + 真实 sha + style 干净)**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
grep -c "postflight do" "$tap/Casks/clipboardapp.rb"
sed -nE 's/^[[:space:]]*(version|sha256) "([^"]*)".*/\1=\2/p' "$tap/Casks/clipboardapp.rb"
brew style "$tap/Casks/clipboardapp.rb"
```
Expected: `postflight do` 计数 `1`;`version=0.1.0`、`sha256=<真实64hex>`;`no offenses detected`。

- [ ] **Step 3: 提交并推送 tap**

Run:
```bash
tap="$PWD/../homebrew-clipboard"
( cd "$tap" && git add Casks/clipboardapp.rb README.md && git commit -m "Strip quarantine via postflight; correct README" && git push )
```
Expected: 推送成功。

- [ ] **Step 4: 确认 tap CI 绿**

查 tap 仓库 Actions 的 `Audit cask`(`brew style` + `brew audit`)最新一次 run,结论为 success。(可用 keychain PAT 调 `GET /repos/anlostsheep/homebrew-clipboard/actions/runs?per_page=1` 轮询 `.status`/`.conclusion`。)

---

### Task 6: 真机 E2E 复验(去 quarantine 生效)并记录验收

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: 全新安装并检查 quarantine**

Run:
```bash
brew update
brew uninstall --cask clipboardapp 2>/dev/null || true
rm -f "$(brew --cache --cask clipboardapp 2>/dev/null)"*
brew install --cask clipboardapp
xattr -p com.apple.quarantine /Applications/ClipboardApp.app 2>&1
```
Expected: 安装成功;`xattr` 输出 `No such xattr: com.apple.quarantine`(postflight 已去掉 quarantine)。

> 说明:若本机设置了 `HOMEBREW_REQUIRE_TAP_TRUST`,首次需 `brew trust anlostsheep/clipboard`(这是本机环境变量触发的信任门,非普通用户默认行为)。

- [ ] **Step 2: 打开无 Gatekeeper + 自动粘贴(维护者手动确认)**

`open -a ClipboardApp` 应直接打开,无"无法验证开发者"拦截;系统设置授予辅助功能后确认自动粘贴可用;`shasum -a 256 -c dist/ClipboardApp-v0.1.0-macos.zip.sha256` 期望 `OK`。

- [ ] **Step 3: 勾选并追加验收记录**

在 `docs/manual-acceptance-checklist.md` 的"分发信任链(Homebrew 免费路)"分区,把这两条从 `- [ ]` 改为 `- [x]`:
- `Homebrew 安装后 App 打开无需 Gatekeeper 右键 Open 步骤。`
- ``xattr -p com.apple.quarantine /Applications/ClipboardApp.app` 无输出。`

并在该分区末尾追加:

```markdown
- 验收记录 2026-07-02:v0.1.0 经 `brew install --cask clipboardapp` 安装后,cask postflight 已移除 quarantine(`xattr` 无输出),App 打开无 Gatekeeper 拦截,辅助功能授权后自动粘贴可用,sha256 校验 OK。免摩擦由 cask postflight 而非 Homebrew 提供。
```

- [ ] **Step 4: 提交并推送**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record v0.1.0 acceptance (postflight quarantine removal verified)"
git push origin master
```

---

## Self-Review

**Spec coverage**(对照 `2026-07-02-clipboard-gatekeeper-quarantine-postflight-design.md`):
- cask postflight 去 quarantine(seed + tap)→ Task 1 + Task 5。✔
- caveats 透明披露 → Task 1(seed)+ Task 5(tap 由 seed 重生成)。✔
- 修正 README/install.md/tap README 错误表述 → Task 2(+ Task 5 同步 tap README)。✔
- release notes 文案校正 → Task 3。✔
- 不发新 release、不改 App 代码、版本保持 0.1.0 → Task 5 用 update-cask 回填 0.1.0,无 app 重建。✔
- E2E 复验(xattr 无 quarantine、无 Gatekeeper、自动粘贴、sha)+ 验收记录 → Task 6。✔
- tap CI 绿(audit 接受 postflight,已实测)→ Task 5 Step 4。✔

**Placeholder scan:** 每个改动步骤给出完整 old→new 文本;postflight 代码、caveats、文档句子均为实际内容,无 TBD/TODO。

**Type/name consistency:** postflight 用 `system_command "/usr/bin/xattr"` + `#{appdir}/ClipboardApp.app`;stanza 顺序 app → postflight → zap → caveats;cask token `clipboardapp`、tap `anlostsheep/clipboard`、版本 `0.1.0`、资产 sha `dist/ClipboardApp-v0.1.0-macos.zip.sha256`、`update-cask.sh <cask> <version> <sha>` 签名,在 seed/tap/文档/验收间一致。
