# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

macOS 剪贴板管理器，使用 Swift Package Manager 构建。核心功能：持续监控系统剪贴板变化、将历史记录持久化到本机 SQLite + payload 文件、通过全局快捷键快速访问 QuickPanel，并支持复制或自动粘贴历史内容。

**技术栈**：Swift 5.10+、SwiftUI、AppKit、Swift Concurrency (actor/async)、macOS 14+

## 常用命令

### 构建与测试

```bash
# 完整验证（测试 + 构建）
Scripts/verify.sh

# 运行所有测试
swift test

# 运行特定测试目标
swift test --filter ClipboardCoreTests
swift test --filter ClipboardPlatformTests

# 构建所有产物
swift build

# 构建特定产物
swift build --product ClipboardApp
swift build --product ClipboardManualProbe

# 构建 .app 包（包含代码签名和图标）
Scripts/build-app-bundle.sh
# 可选环境变量：
# - CONFIGURATION=debug|release (默认 release)
# - BUNDLE_IDENTIFIER (默认 com.local.clipboard-manager)
# - VERSION (默认 0.1.0)
# - CODE_SIGN_IDENTITY (默认自动检测)
# - CODE_SIGN_KEYCHAIN (指定自签名证书所在 keychain)
# - REQUIRE_STABLE_CODE_SIGNING=1 (禁止自动降级到 ad-hoc)

# 一次性创建本机自签名发布证书
Scripts/setup-self-signed-signing.sh

# 使用自签名证书构建稳定发布包
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
```

### 手工测试工具

```bash
# 自检：验证剪贴板写入能力
swift run ClipboardManualProbe self-check

# 检查辅助功能权限状态
swift run ClipboardManualProbe accessibility

# 读取当前剪贴板内容（用于验收测试）
swift run ClipboardManualProbe read-once
```

### 性能测试

```bash
# 大文本处理性能测试
Scripts/perf-large-text.sh
```

## 架构设计

### 模块依赖关系

```
ClipboardCore (核心业务逻辑，无外部依赖)
    ↓
ClipboardPlatform (macOS 系统集成)
    ↓
ClipboardApp (SwiftUI 主应用)
ClipboardManualProbe (手工测试工具)
```

### ClipboardCore 核心模块

- **Models**：数据模型
  - `ClipboardRecord`：历史记录实体
  - `ClipboardCapture`：捕获的剪贴板数据
  - `ClipboardPayload`：支持文本、图片、文件等多种内容类型

- **Monitor**：`ClipboardMonitor` actor，通过轮询检测剪贴板变化

- **Ingest**：捕获处理流程
  - `ClipboardIngestService`：将捕获数据转换为历史记录
  - `ClipboardCaptureCoordinator`：协调监控和存储

- **Storage**：`HistoryStore` 协议及 SQLite / InMemory 实现
  - 支持查询、去重（基于内容 SHA256 哈希）、保留策略、磁盘满自愈、payload 文件清理

- **Paste**：粘贴控制
  - `PasteController`：处理粘贴事务
  - `PasteboardWriting`/`PasteEventPosting` 协议

- **Privacy**：`PrivacyPolicy` 定义忽略规则
  - 过滤敏感应用（密码管理器、银行 App 等）
  - 可选择忽略 Universal Clipboard

- **UI**：`QuickPanelViewModel` actor，处理搜索/选择逻辑

### ClipboardPlatform 平台层

- `SystemPasteboardClient`：实现 `PasteboardReading`、`PasteboardWriting`、`PasteEventPosting` 协议
- 直接调用 AppKit (NSPasteboard) 和 ApplicationServices API

### ClipboardApp 应用层

- `AppServices`：@MainActor 单例，组装所有依赖（依赖注入容器）
- `AppDelegate`：AppKit 入口，组装服务、状态栏、全局快捷键与设置窗口
- `QuickPanelState`：@MainActor ObservableObject，驱动 UI 状态
- `HotKeyManager`：使用 Carbon Events 注册系统级快捷键，并过滤系统保留组合

## 核心流程

### 捕获流程

1. `ClipboardCaptureLoop` 周期性触发捕获
2. `ClipboardMonitor.poll()` 检测剪贴板变化
3. `ClipboardCaptureCoordinator.captureLatestChange()` 捕获数据
4. `ClipboardIngestService.ingest()` 创建历史记录
5. `HistoryStore.upsert()` 去重并持久化存储（基于内容哈希）

### 粘贴流程

1. 用户在 QuickPanel 通过 `Return` 或鼠标单击选择记录
2. `PasteController.paste()` 写入剪贴板
3. 若设置为自动粘贴，则发送 Command-V 事件（需辅助功能权限）
4. 返回 `PasteTransaction` 状态（成功、写入失败、权限缺失、焦点丢失、目标拒绝等）

### 隐私过滤

- `PrivacyPolicy.shouldIgnore()` 检查：
  - 应用 Bundle ID（密码管理器、银行 App）
  - 剪贴板类型（密码类型）
  - Universal Clipboard 标志

## 开发注意事项

### 并发模型

- 使用 Swift Concurrency (actor/async/await)
- 关键 actor：`ClipboardMonitor`、`QuickPanelViewModel`、`InMemoryHistoryStore`、SQLite store actor
- UI 状态必须在 @MainActor 上更新

### 协议驱动设计

- 核心接口定义为协议（`PasteboardReading`、`HistoryStore` 等）
- 便于单元测试（可注入 mock 实现）
- 便于扩展（如替换存储层为数据库）

### 测试策略

- **ClipboardCoreTests**：单元测试核心逻辑（Monitor、Ingest、Privacy、Paste、ViewModel）
- **ClipboardPlatformTests**：集成测试系统 API 调用
- 手工验收测试：参考 `docs/manual-acceptance-checklist.md`

### 大内容处理

- `LargeTextPolicy.classify()` 检测 JSON/YAML/日志/代码
- 生成摘录和元数据，避免在 UI 中渲染完整大文本
- QuickPanel 首屏只显示摘要

### 权限要求

- **辅助功能权限**：模拟 Command-V 按键事件
- 运行期撤销权限时，自动粘贴阻断并提示重新授权
- QuickPanel 仍可在无辅助功能权限时执行“仅复制”行为；自动粘贴不能静默降级

## 验收测试

完整验收清单见 `docs/manual-acceptance-checklist.md`，包括：

- 多种复制来源覆盖（Safari、Chrome、微信、VS Code、Finder 等）
- Universal Clipboard 行为验证
- 粘贴行为验证（自动粘贴 vs 仅复制）
- QuickPanel 快捷键、类型过滤、搜索焦点恢复、鼠标选择和打开时选中策略验证
- macOS 标准快捷键验证（QuickPanel `Command+,`，Settings `Command+W`）
- 辅助功能授权新增/移除后的实时状态刷新验证
- 大内容性能验证
- 失败提示验证

## 代码规范

- 代码注释用英文
- 遵循 Swift API Design Guidelines
- 优先使用协议和依赖注入
- 避免在 actor 外部直接访问可变状态
