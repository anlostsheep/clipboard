# Clipboard

Clipboard 是一个原生 macOS 剪贴板管理器，使用 SwiftPM、SwiftUI、AppKit 和 SQLite 构建。

当前状态是 **early beta**。它已经适合给熟悉 macOS 辅助功能权限和自签名 App 安装流程的小范围开发者/内测用户使用；还不是面向陌生大众用户的 notarized 稳定版。

## 当前可用能力

- 菜单栏 App，不显示 Dock 图标。
- 通过菜单栏图标或 `Command+Shift+V` 打开 QuickPanel。
- 支持搜索、键盘导航、类型过滤、来源 App 图标。
- 支持文本、富文本、链接、图片、文件 URL 历史。
- 支持自动粘贴模式和仅复制模式。
- 支持 `Option+Shift+Enter` 对文本、链接、富文本执行无格式粘贴。
- 支持数字快捷键选择或粘贴当前可见记录。
- 使用 SQLite 持久化历史记录。
- 支持置顶、删除、清除历史和 payload 清理。
- 支持基础隐私控制：暂停采集、忽略下一次复制、忽略剪贴板类型、忽略来源 App、可选忽略 Universal Clipboard。
- 已有 Maccy / Clipaste 导入代码路径和自动化覆盖。
- 可以构建稳定自签名 App 包，用于小范围 beta 分发。

详细验收矩阵和历史记录见 [docs/manual-acceptance-checklist.md](docs/manual-acceptance-checklist.md)。

## 当前限制

- 公开分发包尚未使用 Developer ID 签名和 notarization，首次打开仍需要处理 Gatekeeper 提示。
- 自动粘贴依赖 macOS 辅助功能权限；未授权时仅复制模式仍可把记录写入剪贴板，但不会模拟 `Command+V`。
- 部分手工验收仍未完成：更完整的系统/硬件矩阵、Universal Clipboard 场景、长时间性能、真实 Maccy / Clipaste 数据库导入、部分失败状态 UI。
- 当前还没有正式截图和 release notes，项目定位应视为早期开源 beta，而不是成熟公开产品页。

## 环境要求

- macOS 14 或更新版本。
- Xcode 或 Xcode Command Line Tools，支持 Swift 5.10。
- Apple Silicon 是当前主要验证环境；Intel 覆盖仍在手工验收清单中跟踪。

## 安装

推荐使用 Homebrew:

```bash
brew tap anlostsheep/clipboard
brew install --cask clipboardapp
```

Homebrew 安装 cask 时会去掉 quarantine 属性,App 直接打开,不会遇到 Gatekeeper 首次打开
拦截(尽管本构建是自签名、未公证)。更新用 `brew upgrade --cask clipboardapp`。

不使用 Homebrew 时,也可以从发布包安装。

## 从发布包安装

如果已经有 release zip：

1. 解压 `ClipboardApp.app`。
2. 移动到 `/Applications`。
3. 首次打开时使用 Finder 右键 -> Open，或在终端清除 quarantine：

   ```bash
   xattr -dr com.apple.quarantine /Applications/ClipboardApp.app
   open /Applications/ClipboardApp.app
   ```

4. 按提示在系统设置中授予辅助功能权限。
5. 运行快速检查：

   ```bash
   swift run ClipboardManualProbe accessibility
   ```

授权后期望输出：

```text
accessibility: authorized
```

更完整的安装、更新和卸载说明见 [docs/install.md](docs/install.md)。

## 从源码构建

克隆仓库后运行：

```bash
swift build
swift test
```

主验证门禁：

```bash
Scripts/verify.sh
```

该脚本会运行：

- `swift test`
- `swift build`
- `Scripts/test-automation.sh`

构建本地 App 包：

```bash
CODE_SIGN_IDENTITY=- Scripts/build-app-bundle.sh
open .build/app-bundles/release/ClipboardApp.app
```

ad-hoc 签名适合本地开发，但代码变化后 macOS 可能要求重新确认辅助功能权限。

## 稳定自签名构建

给小范围 beta 用户分发时，建议使用稳定自签名流程：

```bash
Scripts/setup-self-signed-signing.sh

CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
```

验证签名：

```bash
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

期望包含：

```text
Authority=ClipboardApp Local Code Signing
```

更多说明见 [docs/release-signing.md](docs/release-signing.md)。

## 无付费发布流程

不购买 Apple Developer Program 时，推荐发布稳定自签名 zip 和 SHA-256 校验文件：

```bash
VERSION=0.1.0 Scripts/package-release.sh
```

产物默认写入 `dist/`：

```text
ClipboardApp-v0.1.0-macos.zip
ClipboardApp-v0.1.0-macos.zip.sha256
```

该流程不能消除 Gatekeeper 首次打开提示，但能把构建、签名检查、打包和校验文件生成固定下来。维护者流程见 [docs/release-process.md](docs/release-process.md)。

## 手工探针

`ClipboardManualProbe` 是真实剪贴板和隐私策略的轻量诊断工具：

```bash
swift run ClipboardManualProbe self-check
swift run ClipboardManualProbe accessibility
swift run ClipboardManualProbe read-once
```

常用隐私策略检查：

```bash
swift run ClipboardManualProbe policy-universal-ignore
swift run ClipboardManualProbe policy-ignore-type com.example.secret
swift run ClipboardManualProbe policy-ignore-app com.example.Passwords
```

## 隐私模型

Clipboard 只在本机读取系统剪贴板，并把历史记录保存在本机。

- 元数据：`~/Library/Application Support/<bundle-id>/clipboard.sqlite`
- 大 payload：`~/Library/Application Support/<bundle-id>/payloads/`
- 导入报告：`~/Library/Application Support/<bundle-id>/imports/reports/`
- 偏好设置：macOS `UserDefaults`
- 当前代码库不使用网络 API。

默认隐私过滤会忽略常见 concealed / transient pasteboard types，包括部分 1Password 相关剪贴板标记。用户可以暂停采集、忽略下一次复制、忽略 Universal Clipboard、添加忽略剪贴板类型，以及添加忽略来源 App bundle id。

剪贴板历史可能包含敏感数据。提交 issue、PR、截图、日志、benchmark 报告或数据库文件前，必须先确认其中没有真实隐私内容。

## 项目结构

```text
Sources/ClipboardApp              macOS App、QuickPanel、设置页、状态栏
Sources/ClipboardCore             模型、存储、导入、隐私、粘贴逻辑
Sources/ClipboardPlatform         NSPasteboard 和 macOS 平台桥接
Sources/ClipboardManualProbe      手工剪贴板和隐私探针
Sources/ClipboardBenchmarkProbe   benchmark 报告生成器
Tests/                            Core、App、Platform 的 XCTest 覆盖
Scripts/                          验证、签名、benchmark、性能辅助脚本
docs/                             发布签名、验收清单、设计和计划文档
```

## 截图

当前还没有提交正式截图。公开 beta 前建议补充以下截图：

- 菜单栏图标和弹出位置。
- 包含多种历史类型的 QuickPanel。
- Settings -> General。
- Settings -> Privacy。
- 辅助功能权限引导。

截图应使用稳定签名 release 包采集，确保展示内容与分发构建一致。截图中不要包含真实敏感剪贴板内容。

## 发布前验证

发布 beta 包前至少运行：

```bash
git diff --check
VERSION=0.1.0 Scripts/package-release.sh
cd dist
shasum -a 256 -c ClipboardApp-v0.1.0-macos.zip.sha256
```

然后更新 [docs/manual-acceptance-checklist.md](docs/manual-acceptance-checklist.md) 中对应的手工验收记录。

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 安全

见 [SECURITY.md](SECURITY.md)。不要在 issue 或 PR 中提交剪贴板数据库、payload 文件、导入报告、私有签名材料或包含真实剪贴板内容的截图。

## License

Apache License 2.0. See [LICENSE](LICENSE).
