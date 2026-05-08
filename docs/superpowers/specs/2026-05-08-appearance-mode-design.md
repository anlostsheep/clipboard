# 设计文档：外观主题（跟随系统 / 浅色 / 深色）

**日期**：2026-05-08
**状态**：已确认，待实施

## 概述

为 Clipboard 应用增加在 app 内手动覆盖系统外观主题的能力。用户可在「设置 / 通用」中三选一：**跟随系统 / 浅色 / 深色**。

底层事实：Clipboard 当前的 SwiftUI 视图全部使用语义色（`Color.primary`、`Color.secondary`、`Color.accentColor`、`.regularMaterial` 等），亮色模式渲染天然正确，无任何视觉 bug——本次工作**不是新增亮色支持**，而是新增"覆盖系统外观"的开关。

## 范围

**本次设计包含：**

- `AppearanceMode` 枚举（`system` / `light` / `dark`）
- `ClipboardAppSettings.appearanceMode` 持久化（`UserDefaults`）
- `AppearanceController` 极小封装（`NSApp.appearance = ...`）
- `GeneralSettingsView` 新增「外观」Section（置于最顶部）
- `AppDelegate.applicationDidFinishLaunching` 启动时应用一次
- 新建 `ClipboardAppTests` 测试 target

**不在本次范围内（YAGNI）：**

- 按时间自动切换（macOS 系统级已支持）
- 自定义 accent 色 / 主题色
- 菜单栏状态图标外观定制（template image 由系统反色，无法 app 级覆盖）
- 跨设备同步外观偏好

## 实现方案

### 选定方案：`NSApp.appearance` 全局覆盖

| 备选方案 | 是否覆盖 NSMenu 下拉 | 决策 |
|---|---|---|
| **A. `NSApp.appearance`（选定）** | ✅ 自动 | 单点、原子、覆盖完整 |
| B. SwiftUI `.preferredColorScheme` 逐窗口 | ❌ 不覆盖 NSMenu，需额外处理 | 不达"全 app 一致"标准 |

`NSApp.appearance = nil` 表示跟随系统；设为 `NSAppearance(named: .aqua)` 强制亮，`.darkAqua` 强制暗。设置即时生效，所有当前打开的 SwiftUI 窗口、AppKit 窗口、即将弹出的 NSMenu 全部应用。

## 数据模型

新增枚举（位于 `Sources/ClipboardApp/AppSettings.swift`）：

```swift
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}
```

扩展 `ClipboardAppSettings`：

```swift
extension ClipboardAppSettings {
    static let appearanceModeKey = "appearance.mode"

    static func appearanceMode(defaults: UserDefaults = .standard) -> AppearanceMode {
        guard let raw = defaults.string(forKey: appearanceModeKey),
              let mode = AppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }
}
```

**默认值 = `.system`**。新老用户首启行为不变。

## 应用生效路径

新增 `Sources/ClipboardApp/Appearance/AppearanceController.swift`：

```swift
import AppKit

@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }
}
```

**调用点共两处：**

1. **启动时**：`AppDelegate.applicationDidFinishLaunching` 内，**紧跟 `NSApp.setActivationPolicy(.accessory)` 之后、`setupStatusBar()` 之前**调用 `AppearanceController.apply(ClipboardAppSettings.appearanceMode())`。这样状态栏菜单从首帧就携带正确外观。

2. **设置变更时**：`GeneralSettingsView` 的 `Picker` 在 `onChange` 中调用 `AppearanceController.apply(...)`。

无需 NotificationCenter / Combine——`NSApp.appearance = x` 是同步的，所有当前打开窗口立即重绘，之后弹出的 NSMenu 也自动应用。

## 设置 UI

在 `GeneralSettingsView` 中新增 Section，**插入位置：第一个 Section（在「辅助功能权限」之前）**。

```swift
@AppStorage(ClipboardAppSettings.appearanceModeKey)
private var appearanceModeRaw: String = AppearanceMode.system.rawValue

private var appearanceMode: Binding<AppearanceMode> {
    Binding(
        get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
        set: { appearanceModeRaw = $0.rawValue }
    )
}

// 在 Form 内、最顶部：
Section("外观") {
    Picker("色系", selection: appearanceMode) {
        ForEach(AppearanceMode.allCases, id: \.self) { mode in
            Text(mode.displayName).tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .onChange(of: appearanceModeRaw) { _, newRaw in
        let mode = AppearanceMode(rawValue: newRaw) ?? .system
        AppearanceController.apply(mode)
    }
}
```

样式与既有「快捷面板位置」Section 一致（`.segmented` Picker + `.formStyle(.grouped)`），保持视觉协调。

## 测试策略

**新建 `Tests/ClipboardAppTests/` 目录与 `ClipboardAppTests` test target**（在 `Package.swift` 中追加）。新 target 依赖 `ClipboardApp`。

> 此 target 之前不存在；建立后未来 `ClipboardApp` 内的其他 settings helper（`hotkeyKeyCode`、`panelPositionMode` 等）也有了测试归宿，是一次性架构投资。

### 自动化测试

| 测试用例 | 断言 |
|---|---|
| `AppearanceMode_nsAppearance_systemReturnsNil` | `.system.nsAppearance == nil` |
| `AppearanceMode_nsAppearance_lightReturnsAqua` | `.light.nsAppearance?.name == .aqua` |
| `AppearanceMode_nsAppearance_darkReturnsDarkAqua` | `.dark.nsAppearance?.name == .darkAqua` |
| `ClipboardAppSettings_appearanceMode_absentDefaultsToSystem` | 缺 key → `.system` |
| `ClipboardAppSettings_appearanceMode_invalidStringDefaultsToSystem` | 写入 `"garbage"` → `.system` |
| `ClipboardAppSettings_appearanceMode_validValueRoundTrips` | 写入 `"dark"` → `.dark` |

每个测试用一次性 `UserDefaults(suiteName:)` 实例隔离，避免污染全局。

### 手工验收

追加到 `docs/manual-acceptance-checklist.md`：

| 系统外观 | App 设置 | 期望 |
|---|---|---|
| Light | 跟随系统 | QuickPanel/Settings/Welcome/菜单栏下拉全亮 |
| Light | 浅色 | 同上 |
| Light | 深色 | 全暗（不跟随系统） |
| Dark | 跟随系统 | 全暗 |
| Dark | 浅色 | 全亮（不跟随系统） |
| Dark | 深色 | 全暗 |

**特别核对**：在「设置」窗口本身切换 Picker，整窗应**立即**变色，不需要重启 app。

### 不测的部分

- `AppearanceController.apply` 本身——单行 `NSApp.appearance = x`，目测覆盖
- `GeneralSettingsView` 的 SwiftUI 渲染——项目无 SwiftUI 快照测试基础设施，留给手工验收

## 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| `NSApp.appearance` 未在某些早期窗口生效 | Welcome 窗口在首启时可能首帧错色 | 启动调用点放在 `setupStatusBar()` 之前，且**先于** `checkFirstLaunch()` 调用 |
| 用户在设置窗口切色后 QuickPanel 仍是旧色 | 视觉不一致 | `NSApp.appearance =` 是同步广播；如手工验收发现，则改为发 `NSAppearanceDidChange` 通知逐窗刷新（目前预期不需要） |
| 未来 macOS 版本 `NSAppearance.Name` 变更 | 测试失败 | 测试断言用 `.aqua` / `.darkAqua` 常量而非字符串字面值 |

## 验收标准

- [ ] `swift test --filter ClipboardAppTests` 通过 6 个新测试
- [ ] `swift test --filter ClipboardCoreTests` / `ClipboardPlatformTests` 仍全绿（无回归）
- [ ] `Scripts/build-app-bundle.sh` 编译通过、签名通过
- [ ] 手工验收 6 组合全过
- [ ] 设置窗口内切换 Picker 即时生效，无需重启
- [ ] `docs/manual-acceptance-checklist.md` 已追加新条目
