# Clipboard 分发 go-live 收尾(去 gh · curl+PAT 发布)设计

## 背景与现状

分发信任链(免费路 / Homebrew)的设计与实现已基本完成(见
`docs/superpowers/specs/2026-06-24-distribution-trust-chain-homebrew-design.md` 与
`docs/superpowers/plans/2026-06-24-distribution-trust-chain-homebrew.md`),但整条流水线
停在 go-live 收尾这一步,当前状态是:

- 分发功能的全部 commit 只在**本地 `master`**,尚未推到 `origin`(领先 14 个 commit)。
- 工作区有一批**未提交**的改动:cask token 从 `clipboard` 改名为 `clipboardapp`。生产文件
  (README、`docs/install.md`、`Scripts/publish-release.sh`、`docs/release-process.md`、
  验收清单、`packaging/homebrew/`)已改完;仅 `Scripts/tests/test-update-cask.sh` 的测试
  fixture(第 21/25/60 行)还残留 `clipboard` 字样。
- **改名的起因**:go-live 时 tap CI 失败,根因是 cask token `clipboard` 与 homebrew-core
  已有的 `clipboard` formula 冲突,必须改名。tap 名 `anlostsheep/clipboard` 不受影响。
- tap 仓库 `anlostsheep/homebrew-clipboard` 已在 GitHub 创建并 seed,但里面仍是旧的
  `clipboard.rb`,CI 是红的。
- 尚未发布任何真实 release,`brew install` 跑不通。
- 维护者本机**不使用 `gh` CLI**,GitHub 认证走 PAT(存于 macOS keychain,
  `credential.helper=osxkeychain`,条目 `server=github.com / account=anlostsheep`)。而
  `Scripts/publish-release.sh` 目前**硬依赖 `gh`**。

## 目标

把上述停滞收尾,发布第一个可安装的公开 release,让 `brew install --cask clipboardapp` 真正
跑通,并让维护者本机(不装 gh、用 PAT)能一条命令完成后续发布。

## 已定决策

- **Cask token = `clipboardapp`**(避开 homebrew-core 的 `clipboard` 冲突;tap 名
  `anlostsheep/clipboard` 保持不变)。
- **首个公开版本 = `0.1.0`**(与 seed cask 一致;项目自定位 early beta)。
- **执行分工 = 引导式 go-live**:agent 完成本地、可逆动作与 runbook;推 master /
  re-seed tap / 发布 release 在维护者在场时逐步执行,发布这一不可逆步骤前明确确认。
- **发布接入 = GitHub REST API + `curl` + PAT**,彻底去掉 `gh` 依赖;PAT 从 macOS
  keychain 读取(`security find-internet-password -s github.com -a anlostsheep -w`),
  全程不打印、不入 URL。

## 非目标(继承 2026-06-24 设计,本轮不做)

- Notarization / Developer ID 签名。
- Sparkle / appcast / 任何应用内更新检查或应用内网络调用。
- Mac App Store、DMG、提交 homebrew-core。
- 修改 bundle identifier(沿用 `com.local.clipboard-manager`)。
- 把 tap re-seed 或发布进一步"全自动化"(过度自动化与"发布前确认"边界冲突;re-seed 只做
  一次,不值得固化成脚本)。

## 架构与关键改动

主仓库 `anlostsheep/clipboard` 与 tap 仓库 `anlostsheep/homebrew-clipboard` 的两仓库结构
不变。本轮唯一的代码改动是 **`Scripts/publish-release.sh` 的发布段从 `gh` 迁移到
`curl` + PAT**;其余是改名收尾、tap re-seed 与文档/验收更新。

### `publish-release.sh` 发布段改造(限定改动,约 20 行)

- **删除** `gh` 相关:`command -v gh`、`gh auth status`、`gh release view`、
  `gh release create`。
- **Tier-1 参数校验保持最前不变**(`VERSION` 必填、semver 合法、`TAP_REPO_DIR` 必填),
  因此 `Scripts/tests/test-publish-release-preconditions.sh` 不受影响、仍通过。keychain
  读取与任何网络访问只发生在 Tier-2,保持 Tier-1 的 hermetic 性质。
- **Tier-2 新增(在构建/打 tag 之前 fail-fast)**:
  - 从 keychain 读 PAT:`github_token="$(security find-internet-password -s github.com -a anlostsheep -w 2>/dev/null || true)"`;为空则 `die`。
  - 从 `git remote get-url origin` 解析 `owner/repo`(期望 `anlostsheep/clipboard`)。
  - token/仓库可达预检:`GET https://api.github.com/repos/$owner/$repo` 返回 200,否则
    `die`(避免用无效 token 走到不可逆步骤)。
  - release 存在性预检:`GET …/releases/tags/vX.Y.Z` —— 404 = 可发布;200 = 已存在则
    中止(不静默覆盖);其它 = 报 `HTTP <code>` 错。
- **发布(本地产物齐备、tag 已推之后)**:
  - `POST …/releases` 建 release(`tag_name`/`name`/`body`)。release notes 的 JSON
    转义用 `jq` 或 `python3`(取机器上存在者)。
  - 从返回体解析 `upload_url`。
  - 上传资产:分别 `POST "$upload_url?name=<file>"` 传 zip 与 `.sha256`
    (`Content-Type: application/octet-stream`,`--data-binary @file`)。
- **认证**:`Authorization: Bearer $github_token`;所有 curl 用 `-sS`,token 绝不 echo、
  绝不进 URL。
- `git tag -a` + `git push origin "$tag"` **不动**(keychain 的 PAT 已能 push)。
- 同步更新 `docs/release-process.md`:把前置条件里"gh 已登录"改为 PAT/keychain 说明。

## 分阶段执行序列(agent / 维护者 · 每阶段验证)

顺序与 `publish-release.sh` 前置校验对齐("干净工作树 + 在 master + tag 不存在 + PAT 可用
+ tap 可达 + release 不存在"):

| # | 阶段 | 谁 | 动作 | 验证 |
|---|------|----|------|------|
| 0 | 本地改名收尾 | agent | 把 `Scripts/tests/test-update-cask.sh` fixture 残留 `clipboard`(21/25/60 行)改为 `clipboardapp`,与工作区改动一起提交为一个聚焦 commit(`build: rename cask token to clipboardapp…`) | `git diff --check` 无告警 |
| 1 | 本地绿色门禁 | agent | `Scripts/verify.sh` + `test-update-cask.sh` + `test-publish-release-preconditions.sh` + `brew style` cask | 全绿才继续 |
| 2 | 推送主仓库 | agent(推前确认) | 确认 repo public;`git push origin master` | `git status` = up to date |
| 3 | 校验 PAT 可用 | agent | keychain 读 PAT;`GET /repos/anlostsheep/clipboard` == 200(fail-fast,无需装/登录 gh) | 返回 200 |
| 4 | 用 clipboardapp re-seed tap | agent(推前确认) | clone/pull `../homebrew-clipboard`;`git rm Casks/clipboard.rb`;拷入 `Casks/clipboardapp.rb`;同步 tap `README.md`(audit.yml 无硬编码 token,不改);提交 + push | tap Actions `Audit cask` 变绿 |
| 5 | 发布 v0.1.0 | 维护者明确 go 后执行(不可逆) | `TAP_REPO_DIR=…/homebrew-clipboard VERSION=0.1.0 Scripts/publish-release.sh`(已改造的 curl+PAT 版) | GitHub 有 Release v0.1.0(zip+sha);tap commit `clipboardapp 0.1.0` 且 cask sha 与资产一致;`codesign -dv` 显示稳定签名 Authority |
| 6 | E2E 验收并记录 | 维护者 + agent | `brew update && brew install --cask clipboardapp`;`open`;`xattr` quarantine 检查;授权自动粘贴;`shasum -c`;勾选验收清单并追加日期记录后 commit | quarantine 无输出、自动粘贴可用、sha OK |

## 数据流

```
维护者:  publish-release.sh(curl+PAT) -> GitHub Release + 回写 tap cask
安装:    brew tap -> brew install --cask clipboardapp -> Homebrew 去 quarantine -> 直接打开
更新:    brew upgrade --cask clipboardapp -> 拉新 Release 资产(校验 sha256)-> 替换 .app
```

## 错误处理与半发布恢复

- **fail-fast 预检**:token 无效 / 仓库不可达 / release 已存在,都在**构建与打 tag 之前**
  中止,不留悬空 tag 或 release。
- **顺序减小半发布窗口**:先备齐全部本地产物(build、zip、sha),再做任何远端推送(tag →
  release → 上传资产 → 回写 tap)。
- **半发布恢复**:若 release 已建但资产上传失败,脚本中止并保留错误;恢复动作为"删除该
  半成品 release + 对应远端 tag,再重跑"。此恢复步骤记入 `docs/release-process.md`。
- **不静默覆盖**:release 存在性预检命中则拒绝执行。

## 风险

- **curl 发布段无法完全 hermetic 测试**:首个真实 release(Phase 5)即为其验证。缓解为
  Phase 5 前的 token/仓库/release fail-fast 预检,以及"本地产物先于远端推送"的顺序。
- **`clipboardapp` 自身冲突**:由 tap CI 的 `brew audit`(Phase 4)权威兜底;`brew style`
  本地已过。
- **token 泄露**:全程 `-sS` + `Authorization: Bearer`,不进 URL、不 echo。
- **seed cask 漂移**:`packaging/homebrew/Casks/clipboardapp.rb` 发布后仍为 `0.1.0`/
  `0000…`;它只是 bootstrap 源,`publish-release.sh` 只回写 tap 里的 cask。此为设计如此,
  非缺陷。

## 完成标准

1. `clipboardapp` 改名收尾已提交,本地门禁(`verify.sh` + 两个 shell 测试 + `brew style`)
   全绿。
2. `master` 已推 `origin`;repo 为 public。
3. tap 用 `clipboardapp` re-seed,`Audit cask` CI 绿(token 冲突消除)。
4. `publish-release.sh` 去 `gh`、走 `curl`+PAT(keychain),一条命令发出稳定签名的 v0.1.0
   并原子回写 tap cask。
5. `brew install --cask clipboardapp` 无 Gatekeeper 拦截打开;`xattr -p com.apple.quarantine`
   无输出;辅助功能授权后自动粘贴可用;`shasum -a 256 -c` OK。
6. `docs/manual-acceptance-checklist.md` 勾选"分发信任链"条目并追加日期化验收记录;
   `docs/release-process.md` 反映 PAT/curl 发布与半发布恢复。
7. 仍无任何应用内网络调用;notarize / Sparkle / App Store / bundle-id 变更保持范围外。

## 手工验收(追加到 `docs/manual-acceptance-checklist.md` 的现有"分发信任链"分区)

- 全新 Homebrew 安装:`brew tap anlostsheep/clipboard && brew install --cask clipboardapp`
  成功。
- Homebrew 安装后 App 打开无需 Gatekeeper 右键 Open 步骤。
- `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` 无输出。
- 授予辅助功能权限后自动粘贴可用。
- `brew upgrade --cask clipboardapp` 从版本 N 升到 N+1(存在后续版本后验证)。
- 辅助功能权限在 Homebrew 升级后仍保持(稳定签名守住)。
- `brew uninstall --cask --zap clipboardapp` 移除 App 及本机数据目录。
- 直接下载 zip 路径在文档化的 Gatekeeper 绕过步骤下仍可用。
