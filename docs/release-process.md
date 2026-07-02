# 无付费 macOS 发布流程

本项目支持不购买 Apple Developer Program 的小范围 beta 发布路径。

目标是降低构建、签名检查、打包和安装说明的摩擦，但不声称具备 Apple Developer ID 签名或 notarization。用户首次启动时仍需要手动批准 App。

## 发布产物

每个 beta release 至少附带：

- `ClipboardApp-vX.Y.Z-macos.zip`
- `ClipboardApp-vX.Y.Z-macos.zip.sha256`
- release notes，说明验证状态、已知限制和未 notarized 的首次启动流程

不要上传签名 keychain、证书私钥、本地日志、`.build/`、原始剪贴板数据库或 payload 文件。

## 一次性签名准备

创建稳定的本地自签名代码签名身份：

```bash
Scripts/setup-self-signed-signing.sh
```

默认签名材料：

- Identity: `ClipboardApp Local Code Signing`
- Keychain: `~/Library/Keychains/clipboard-signing.keychain-db`
- Keychain password: `clipboard-local-signing`

生成的 keychain 和私钥只保留在维护者机器上，不要提交到仓库，也不要上传到 release。

## 构建发布包

运行一条命令完成验证、构建、打包和校验文件生成：

```bash
VERSION=0.1.0 Scripts/package-release.sh
```

默认会执行：

- `Scripts/verify.sh`
- `Scripts/build-app-bundle.sh`，并设置 `REQUIRE_STABLE_CODE_SIGNING=1`
- 使用 `ditto --keepParent --norsrc --noextattr` 生成 zip
- 生成 SHA-256 校验文件
- 使用 `codesign -dv --verbose=4` 输出签名细节

期望输出：

```text
release package: .../dist/ClipboardApp-v0.1.0-macos.zip
checksum: .../dist/ClipboardApp-v0.1.0-macos.zip.sha256
```

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
- 调 `Scripts/update-cask.sh` 把新 `version`/`sha256` 写进 tap 的 `Casks/clipboardapp.rb`,
  并在 tap 仓库提交、推送。

构建与稳定签名全程在本地完成;只有 `gh` 发布动作触网。App 自身不引入任何网络调用。

## Homebrew Tap 维护

tap 仓库 `anlostsheep/homebrew-clipboard` 的初始内容来自本仓库的 `packaging/homebrew/`。
首次 bootstrap 见 `docs/superpowers/plans/2026-06-24-distribution-trust-chain-homebrew.md`
的 go-live 步骤。bootstrap 之后,tap 仓库是 cask 的权威来源,`publish-release.sh` 每次发版
原子地回写它的 `version` 与 `sha256`。tap 仓库的 CI(`.github/workflows/audit.yml`)对
cask 跑 `brew style` 与 `brew audit`。

## 常用覆盖项

指定版本号：

```bash
VERSION=0.2.0 Scripts/package-release.sh
```

在公开发布线固定前，指定真实 bundle identifier：

```bash
BUNDLE_IDENTIFIER=dev.example.clipboard VERSION=0.2.0 Scripts/package-release.sh
```

指定输出目录：

```bash
DIST_DIR="$PWD/release-artifacts" VERSION=0.2.0 Scripts/package-release.sh
```

显式打一个 ad-hoc 测试包：

```bash
CODE_SIGN_IDENTITY=- REQUIRE_STABLE_CODE_SIGNING=0 VERSION=0.2.0 Scripts/package-release.sh
```

已经跑过完整验证、只重跑打包时，可以跳过验证：

```bash
RUN_VERIFY=0 VERSION=0.2.0 Scripts/package-release.sh
```

## 本地产物核验

验证 zip 校验和：

```bash
cd dist
shasum -a 256 -c ClipboardApp-v0.1.0-macos.zip.sha256
```

检查 App 签名：

```bash
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

默认自签名路径应包含：

```text
Authority=ClipboardApp Local Code Signing
```

Gatekeeper 对未 notarized 的自签名 App 仍可能拒绝或警告：

```bash
spctl -a -vv --type execute .build/app-bundles/release/ClipboardApp.app
```

这是无付费路径的预期限制，不应作为 release 阻塞项记录。

## 手工发布清单

发布前确认：

- `Scripts/package-release.sh` 成功完成。
- `dist/` 中生成 zip 和 `.sha256` 文件。
- 签名是稳定自签名，不是 ad-hoc，除非该包明确标注为本地测试包。
- 尽量在干净用户或另一台 macOS 上把 zip 解压并安装到 `/Applications`。
- `docs/install.md` 中的首次启动说明与当前 macOS 提示一致。
- Accessibility 授权和基础复制/粘贴流程可用。
- 更新 `docs/manual-acceptance-checklist.md` 中对应的手工验收记录。
- release notes 明确说明该包不是 Developer ID 签名，也没有 notarization。

## 对用户的表述

beta release 可以直接说明：

```text
这是一个未 notarized 的开源 beta 构建。它使用稳定的本地自签名身份签名，适合小范围测试；macOS 首次启动时仍需要手动批准。
```

不要写 Apple certified、notarized、trusted by Gatekeeper、no warning 等表述，除非项目未来迁移到付费 Developer ID 签名和 notarization。
