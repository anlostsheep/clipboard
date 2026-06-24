# Contributing

Clipboard 处于 early beta。欢迎贡献，但因为剪贴板 App 会接触敏感数据和 macOS 隐私权限，所有改动都应保持范围清晰、证据充分。

## 开发环境

要求：

- macOS 14 或更新版本。
- Xcode 或 Xcode Command Line Tools，支持 Swift 5.10。

验证当前 checkout：

```bash
Scripts/verify.sh
```

构建本地 UI 测试用 App 包：

```bash
CODE_SIGN_IDENTITY=- Scripts/build-app-bundle.sh
open .build/app-bundles/release/ClipboardApp.app
```

如果要验证辅助功能权限在多次构建之间是否稳定，使用稳定自签名构建：

```bash
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
```

## 修改原则

- 每个 PR 聚焦一个行为、一个问题或一个文档目的。
- 优先沿用已有 target、helper 和脚本，不为单次用途增加抽象。
- 除非改动目标明确需要，否则不要改变默认行为和共享契约。
- 不提交生成的 App 包、本地 keychain、证书、私钥、剪贴板数据库、payload 文件、导入报告、包含敏感内容的截图或 `.build/` 产物。
- 如果改动影响用户可见行为，需要补充测试，并更新相关手工验收项。

## 测试要求

开发中先跑最小相关测试，提交前跑完整门禁：

```bash
swift test --filter <RelevantTestSuite>
Scripts/verify.sh
git diff --check
```

涉及剪贴板、辅助功能权限或 UI 行为时，也使用：

```bash
swift run ClipboardManualProbe self-check
swift run ClipboardManualProbe accessibility
swift run ClipboardManualProbe read-once
```

涉及发布打包或辅助功能身份时，还要构建并检查签名：

```bash
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

## PR 检查清单

- 改动范围和问题描述一致。
- `Scripts/verify.sh` 通过。
- `git diff --check` 通过。
- 用户可见行为变化有对应测试。
- 自动化无法覆盖的真实 macOS 行为已更新手工验收记录。
- 新文档优先链接已有脚本或文档，不复制过长命令说明。
- 没有提交敏感剪贴板数据、证书、keychain 或生成二进制。

## 手工验收

真实 macOS 行为优先记录在 [docs/manual-acceptance-checklist.md](docs/manual-acceptance-checklist.md)，尤其是：

- 辅助功能权限授权/撤销。
- QuickPanel 键盘和鼠标交互。
- 富文本、图片、文件 URL、大文本剪贴板流。
- 稳定签名和首次启动行为。
- 使用真实数据库验证 Maccy / Clipaste 导入。
