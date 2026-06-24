# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

原生 macOS 剪贴板管理器，Swift Package Manager 构建，定位为 early beta。菜单栏 App（无 Dock 图标），通过全局快捷键打开 QuickPanel；持续轮询系统剪贴板、将历史持久化到本机 SQLite + payload 文件，并支持复制或自动粘贴历史内容。无任何网络调用。

**技术栈**：Swift 5.10+、SwiftUI、AppKit、Carbon（全局快捷键）、Swift Concurrency (actor/async)、SQLite、macOS 14+，主要在 Apple Silicon 验证。

## 常用命令

### 验证门禁

```bash
Scripts/verify.sh          # 提交前主门禁
```

`verify.sh` 依次执行三步，三步合起来才是完整覆盖：

1. `swift test` —— 跑全部三个测试 target（含 `ClipboardAppTests`）
2. `swift build` —— 构建全部产物
3. `Scripts/test-automation.sh` —— 只跑 `ClipboardCoreTests` + `ClipboardPlatformTests`，再单独构建 `ClipboardApp` 和 `ClipboardManualProbe`

注意：`test-automation.sh` **不**单独跑 `ClipboardAppTests`，App 层测试只在第 1 步的全量 `swift test` 中被覆盖。

### 构建与测试

```bash
swift build                                   # 全部产物
swift build --product ClipboardApp            # 单个产物（其它：ClipboardManualProbe / ClipboardBenchmarkProbe）

swift test                                    # 全部测试
swift test --filter ClipboardCoreTests        # 单个 target（其它：ClipboardPlatformTests / ClipboardAppTests）
swift test --filter ClipboardCoreTests/PrivacyPolicyTests          # 单个测试类
swift test --filter ClipboardCoreTests/PrivacyPolicyTests/testFoo  # 单个测试方法
```

### App 包构建与签名

```bash
# 本地开发（ad-hoc 签名；改代码后系统可能要求重新授予辅助功能权限）
CODE_SIGN_IDENTITY=- Scripts/build-app-bundle.sh
open .build/app-bundles/release/ClipboardApp.app

# 一次性创建本机自签名证书
Scripts/setup-self-signed-signing.sh

# 稳定自签名构建（用于小范围 beta；辅助功能权限在多次构建间保持稳定）
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh

codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app   # 期望 Authority=ClipboardApp Local Code Signing
```

`build-app-bundle.sh` 关键环境变量：`CONFIGURATION`(debug|release，默认 release)、`BUNDLE_IDENTIFIER`、`VERSION`、`CODE_SIGN_IDENTITY`、`CODE_SIGN_KEYCHAIN`、`REQUIRE_STABLE_CODE_SIGNING=1`(禁止自动降级到 ad-hoc)。

### 发布打包（无付费 Apple Developer Program）

```bash
VERSION=0.1.0 Scripts/package-release.sh      # 默认先跑 verify.sh，再生成 dist/ 下 zip + .sha256
```

`package-release.sh` 默认 `RUN_VERIFY=1`、`REQUIRE_STABLE_CODE_SIGNING=1`。无法消除 Gatekeeper 首次打开提示。维护者流程见 `docs/release-process.md`。

### 手工探针 / 性能

```bash
swift run ClipboardManualProbe self-check                       # 验证剪贴板写入能力
swift run ClipboardManualProbe accessibility                    # 检查辅助功能权限（期望 "accessibility: authorized"）
swift run ClipboardManualProbe read-once                        # 读取当前剪贴板（验收用）
swift run ClipboardManualProbe policy-universal-ignore          # 隐私策略检查
swift run ClipboardManualProbe policy-ignore-type com.example.secret
swift run ClipboardManualProbe policy-ignore-app com.example.Passwords

Scripts/perf-large-text.sh                                      # 大文本处理性能
Scripts/benchmark-maccy-replacement.sh                          # 通过 ClipboardBenchmarkProbe 生成对比报告
```

## 架构设计

### 模块依赖

```
ClipboardCore (核心业务逻辑，零外部依赖)
    ↓
ClipboardPlatform (NSPasteboard / ApplicationServices 桥接)
    ↓
ClipboardApp / ClipboardManualProbe / ClipboardBenchmarkProbe
```

核心接口都是协议（`HistoryStore`、`ClipboardPayloadStore`、`PasteboardReading`/`Writing`、`PasteEventPosting`、`StorageFailureHandler` 等），便于注入 mock 与替换实现。**修改时优先扩展协议而非具体类型。**

### 依赖注入与启动装配（`AppServices`，最重要）

`AppServices`（`@MainActor`、`ObservableObject`）是唯一的 DI 容器，`init` 里手工装配所有依赖、启动捕获循环，并暴露 `@Published storageHealth` / `capturePaused` 给 UI。`AppDelegate` 是 AppKit 入口，负责状态栏、全局快捷键、设置窗口。

`init` 中两个非显而易见的约束：

- **`HealthBox` 间接引用**：`DefaultStorageFailureHandler` 需要回写 `AppServices.storageHealth`，但 Swift 不允许在所有 stored property 初始化完成前捕获 `self`。`HealthBox` 是一个持有 `weak owner` 的占位对象，先创建闭包、最后再 `healthBox.owner = self`。改动 `init` 顺序时务必保留这一模式。
- **启动失败重试循环**：`makeStorage` 在 `while true` 中尝试构建 SQLite 存储；失败时弹模态对话框（在 Finder 显示 / 重试 / 仅本次会话运行 / 退出）。选"重试"则继续循环；选"仅本次会话"则降级为 `InMemoryHistoryStore` 并标记 `storageHealth = .disabled`。

### 存储层装饰器链（最重要）

持久化存储是一条装饰器链，只在 `AppServices.makeStorage` 中组装，任何单个文件都看不到全貌：

```
PayloadCleaningHistoryStore   (最外层：记录删除时同步清理 payload 文件)
   └─ SelfHealingHistoryStore (Layer 1：磁盘满时自动 evict 重试)
        └─ SQLiteHistoryStore (实际 SQLite 持久化 + 保留策略 + 完整性检查)
```

- 去重基于内容 SHA256（`Hashing/ClipboardContentHasher`）；`upsert` 命中已存在 hash 时只递增 `copyCount`。
- 启动后 5 秒，`Task.detached` 执行一次孤儿 payload 扫描：删除数据库未引用的 payload 文件。
- `InMemoryHistoryStore` 是测试与降级用的内存实现，同时实现 `ImportWritableHistoryStore` 与 `HistoryMutationStore`。

### 两层磁盘满（SQLITE_FULL）处理

Layer 1 与 Layer 2 互相独立，只读其一会得到错误结论：

- **Layer 1（自愈）**：`SelfHealingHistoryStore` 装饰器在写入遇满时自动驱逐最旧的非豁免记录并重试。
- **Layer 2（用户策略）**：`AppServices` 里的 `DefaultStorageFailureHandler` 读取 `ClipboardAppSettings.storageFailureStrategy()`：
  - `.continueEvicting`：驱逐 10% 最旧记录后让调用方重试；无可删则暂停监控。
  - `.pauseMonitoring`：暂停 `ClipboardMonitor`。
  - `.skipRecord`：跳过当前这条。
  - 所有路径通过 `StorageHealthNotifier` 推送用户通知，并更新 `storageHealth`。

`evictOldest(percent:)` 只删 `isPinned=false && isFavorite=false && retentionExempt=false` 的记录，返回实际删除数，`percent<=0` 返回 0。

### 捕获流程

1. `ClipboardCaptureLoop` 周期触发（QuickPanel 打开前也会主动 `captureLatestChange()` 抓一次）。
2. `ClipboardMonitor.poll()`（actor）检测剪贴板变化。
3. `ClipboardCaptureCoordinator` 协调：先经 `CaptureControlService.evaluate()` 做准入判定，再 `ingest` + `payloadStore.save`，写入失败交给 `StorageFailureHandler`。
4. `ClipboardIngestService.ingest()` 创建记录（含 `LargeTextPolicy` 大文本分类）。
5. `HistoryStore.upsert()` 去重并持久化。

`CaptureControlService`（actor）是采集准入的唯一闸门，按序判定：`paused` → `ignoreNextCopy`（一次性）→ 隐私（Universal Clipboard / 来源 App bundle id / 忽略的 pasteboard type / 纯 transient 类型）。"暂停采集 / 忽略下一次复制 / 隐私策略变更"都通过 `AppServices` 转发到这里。

### 粘贴流程

1. QuickPanel 中 `Return` 或鼠标单击选择记录（`Option+Shift+Enter` 走无格式粘贴 `PlainTextPastePayload`）。
2. `PasteController.paste()` 写入剪贴板。
3. 自动粘贴模式下发送 Command-V 事件（需辅助功能权限）。
4. 返回 `PasteTransaction` 状态（成功、写入失败、权限缺失、焦点丢失、目标拒绝等）。无辅助功能权限时降级为"仅复制"，**绝不静默模拟按键**。

### 导入子系统

`ImportService` 只在底层 store 实现 `ImportWritableHistoryStore`（`record(forContentHash:)` + `importRecord`）时才装配。`Import/` 下：`MaccyImporter` / `ClipasteImporter` 经 `ExternalSQLiteDatabase` 读取外部库，`ImportSourceDiscovery` 发现安装位置，`ImportSnapshotService` 生成快照，导入报告写入 `imports/reports/`。

### 历史变更

QuickPanel 的置顶 / 删除 / 清除经 `HistoryMutationService`，对应 `HistoryMutationStore` 协议（`deleteRecord` / `replaceRecord` / `clearUnpinned`）。

## 数据位置

- 元数据：`~/Library/Application Support/<bundle-id>/clipboard.sqlite`
- 大 payload：`~/Library/Application Support/<bundle-id>/payloads/`
- 导入报告：`~/Library/Application Support/<bundle-id>/imports/reports/`
- 偏好设置：macOS `UserDefaults`（`ClipboardAppSettings`）

剪贴板历史可能含敏感数据。**禁止**把数据库、payload 文件、导入报告、keychain/证书、含真实剪贴板内容的截图提交进仓库或贴进 issue/PR。

## 开发注意事项

### 并发模型

Swift Concurrency (actor/async/await)。关键 actor：`ClipboardMonitor`、`CaptureControlService`、`QuickPanelViewModel`、`InMemoryHistoryStore`、SQLite store。UI 状态必须在 `@MainActor` 更新。

### 大内容处理

`LargeTextPolicy.classify()` 检测 JSON/YAML/日志/代码，生成摘录与元数据，避免在 UI 渲染完整大文本；QuickPanel 首屏只显示摘要。

### 权限要求

辅助功能权限用于模拟 Command-V。运行期撤销权限会实时阻断自动粘贴并提示重新授权（`AccessibilityPermissionState` 驱动）。

### 全局快捷键

`HotKeyManager`（Carbon Events）注册系统级快捷键并过滤系统保留组合；`HotKeyConflictDetector`（Core）做冲突检测；`HotKeyRecorderView` 是设置页录制 UI。默认 `Command+Shift+V` 打开 QuickPanel。

## 验收与设计文档

- 手工验收矩阵（自动化无法覆盖的真实 macOS 行为）：`docs/manual-acceptance-checklist.md` —— 用户可见行为变更后必须更新。
- 设计 spec / 实施 plan：`docs/superpowers/specs/` 与 `docs/superpowers/plans/`（按日期与特性命名，是理解某个特性"为什么这么做"的权威来源）。
- 发布 / 签名 / 安装：`docs/release-process.md`、`docs/release-signing.md`、`docs/install.md`。
- 贡献规范：`CONTRIBUTING.md`（PR 单一聚焦、提交前过 `Scripts/verify.sh` + `git diff --check`）。

## 代码规范

- 代码注释用英文；遵循 Swift API Design Guidelines。
- 优先协议 + 依赖注入；不为单次用途引入抽象。
- 不在 actor 外部直接访问其可变状态。
- 不改变默认行为与共享契约，除非任务明确要求。
