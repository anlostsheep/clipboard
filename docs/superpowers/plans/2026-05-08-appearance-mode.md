# Appearance Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app override for system appearance (跟随系统 / 浅色 / 深色) via a Settings Picker, applied app-wide using `NSApp.appearance`.

**Architecture:** A small `AppearanceMode` enum with a `nsAppearance` mapping; a one-line `AppearanceController.apply(...)` wrapper around `NSApp.appearance`; called twice — once at `applicationDidFinishLaunching` (boot), once on Picker `onChange` (live). Persistence via `@AppStorage("appearance.mode")`.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit (`NSApp`, `NSAppearance`), Swift Package Manager (`swift test`).

**Spec:** `docs/superpowers/specs/2026-05-08-appearance-mode-design.md`

---

## File Map

| Action | Path | Purpose |
|---|---|---|
| Modify | `Package.swift` | Add `ClipboardAppTests` testTarget |
| Modify | `Sources/ClipboardApp/AppSettings.swift` | Add `import AppKit`, `AppearanceMode` enum, `appearanceModeKey`, `appearanceMode(defaults:)` helper |
| Create | `Sources/ClipboardApp/Appearance/AppearanceController.swift` | `@MainActor enum AppearanceController { static func apply(_:) }` |
| Modify | `Sources/ClipboardApp/App/AppDelegate.swift` | Call `AppearanceController.apply(...)` at boot |
| Modify | `Sources/ClipboardApp/Settings/GeneralSettingsView.swift` | Insert "外观" Section as first Section in Form |
| Create | `Tests/ClipboardAppTests/AppearanceModeTests.swift` | Unit tests for `nsAppearance` mapping |
| Create | `Tests/ClipboardAppTests/ClipboardAppSettingsAppearanceTests.swift` | Unit tests for `appearanceMode(defaults:)` fallback |
| Modify | `docs/manual-acceptance-checklist.md` | Append 6-row appearance verification table |

---

## Task 1: Bootstrap `ClipboardAppTests` target with `AppearanceMode.nsAppearance` tests (red → green)

**Files:**
- Modify: `Package.swift:34-44`
- Create: `Tests/ClipboardAppTests/AppearanceModeTests.swift`
- Modify: `Sources/ClipboardApp/AppSettings.swift:1-3` (add `import AppKit`) and end-of-file (add enum)

- [ ] **Step 1: Add `ClipboardAppTests` target to `Package.swift`**

In `Package.swift`, add a new `.testTarget(...)` entry to the `targets` array, immediately after `ClipboardPlatformTests`:

```swift
    .testTarget(
      name: "ClipboardCoreTests",
      dependencies: ["ClipboardCore"],
      path: "Tests/ClipboardCoreTests"
    ),
    .testTarget(
      name: "ClipboardPlatformTests",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Tests/ClipboardPlatformTests"
    ),
    .testTarget(
      name: "ClipboardAppTests",
      dependencies: ["ClipboardApp"],
      path: "Tests/ClipboardAppTests"
    )
```

> Note: depending on a Swift Package executable target (`ClipboardApp`) from a test target works on Swift 5.10 / macOS 14+; SwiftPM will compile the executable's sources into a testable module. If a future change splits ClipboardApp into a library + thin executable shim, the dependency stays the same.

- [ ] **Step 2: Create the failing test file**

Create `Tests/ClipboardAppTests/AppearanceModeTests.swift` with the full content:

```swift
import AppKit
import XCTest
@testable import ClipboardApp

final class AppearanceModeTests: XCTestCase {
    func test_nsAppearance_systemReturnsNil() {
        XCTAssertNil(AppearanceMode.system.nsAppearance)
    }

    func test_nsAppearance_lightReturnsAqua() {
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
    }

    func test_nsAppearance_darkReturnsDarkAqua() {
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }
}
```

- [ ] **Step 3: Run tests — expect compile failure**

Run:
```bash
swift test --filter ClipboardAppTests 2>&1 | tail -20
```

Expected output contains: `error: cannot find 'AppearanceMode' in scope` (or similar). This confirms the target is wired up but the type doesn't exist yet.

- [ ] **Step 4: Add `import AppKit` and `AppearanceMode` enum to `AppSettings.swift`**

In `Sources/ClipboardApp/AppSettings.swift`, change the imports at the top from:

```swift
import Foundation
import Carbon
```

to:

```swift
import AppKit
import Foundation
import Carbon
```

Then append the enum to the end of the file (after the existing `PanelPositionMode` enum, outside `ClipboardAppSettings`):

```swift

// MARK: - Appearance Mode

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

- [ ] **Step 5: Run tests — expect 3 passing**

Run:
```bash
swift test --filter ClipboardAppTests 2>&1 | tail -10
```

Expected: `Test Suite 'AppearanceModeTests' passed at ...` with `Executed 3 tests, with 0 failures`.

- [ ] **Step 6: Verify other test suites still pass (no regression)**

Run:
```bash
swift test 2>&1 | tail -15
```

Expected: all suites green (`ClipboardCoreTests`, `ClipboardPlatformTests`, `ClipboardAppTests` all pass).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources/ClipboardApp/AppSettings.swift Tests/ClipboardAppTests/AppearanceModeTests.swift
git commit -m "test(app): add ClipboardAppTests target and AppearanceMode enum

- 在 Package.swift 中添加 ClipboardAppTests test target
- 在 AppSettings.swift 中新增 AppearanceMode 枚举（system/light/dark）
- 测试 nsAppearance 三分支映射（nil / .aqua / .darkAqua）"
```

---

## Task 2: Add `ClipboardAppSettings.appearanceMode(defaults:)` helper with fallback tests

**Files:**
- Create: `Tests/ClipboardAppTests/ClipboardAppSettingsAppearanceTests.swift`
- Modify: `Sources/ClipboardApp/AppSettings.swift` (add `appearanceModeKey` constant and `appearanceMode(defaults:)` static method inside `ClipboardAppSettings` enum)

- [ ] **Step 1: Create the failing test file**

Create `Tests/ClipboardAppTests/ClipboardAppSettingsAppearanceTests.swift` with full content:

```swift
import XCTest
@testable import ClipboardApp

final class ClipboardAppSettingsAppearanceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.appearance.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_appearanceMode_absentDefaultsToSystem() {
        XCTAssertEqual(ClipboardAppSettings.appearanceMode(defaults: defaults), .system)
    }

    func test_appearanceMode_invalidStringDefaultsToSystem() {
        defaults.set("garbage", forKey: ClipboardAppSettings.appearanceModeKey)
        XCTAssertEqual(ClipboardAppSettings.appearanceMode(defaults: defaults), .system)
    }

    func test_appearanceMode_validValueRoundTrips() {
        defaults.set(AppearanceMode.dark.rawValue, forKey: ClipboardAppSettings.appearanceModeKey)
        XCTAssertEqual(ClipboardAppSettings.appearanceMode(defaults: defaults), .dark)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

Run:
```bash
swift test --filter ClipboardAppSettingsAppearanceTests 2>&1 | tail -15
```

Expected: compile error mentioning `appearanceModeKey` or `appearanceMode(defaults:)` not found.

- [ ] **Step 3: Add helper to `AppSettings.swift`**

Inside the `ClipboardAppSettings` enum body, append a new `// MARK: - Appearance` section. Place it after the existing `// MARK: - History` section (just before the closing `}` of `ClipboardAppSettings`):

```swift

    // MARK: - Appearance
    static let appearanceModeKey = "appearance.mode"

    static func appearanceMode(defaults: UserDefaults = .standard) -> AppearanceMode {
        guard let raw = defaults.string(forKey: appearanceModeKey),
              let mode = AppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }
```

- [ ] **Step 4: Run tests — expect 3 passing**

Run:
```bash
swift test --filter ClipboardAppSettingsAppearanceTests 2>&1 | tail -10
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Run full test suite — no regression**

Run:
```bash
swift test 2>&1 | tail -15
```

Expected: all tests green.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardApp/AppSettings.swift Tests/ClipboardAppTests/ClipboardAppSettingsAppearanceTests.swift
git commit -m "feat(app): persist AppearanceMode in UserDefaults with fallback

ClipboardAppSettings.appearanceMode(defaults:) 在 key 缺失或脏数据时
回退到 .system，避免用户数据损坏导致 app 启动异常。"
```

---

## Task 3: Add `AppearanceController` (no test, manual verify per spec §测试策略)

**Files:**
- Create: `Sources/ClipboardApp/Appearance/AppearanceController.swift`

- [ ] **Step 1: Create the file**

Create `Sources/ClipboardApp/Appearance/AppearanceController.swift` with full content:

```swift
import AppKit

/// Applies an `AppearanceMode` to the current `NSApplication`. Setting
/// `NSApp.appearance` is synchronous and broadcasts to all open windows
/// and to subsequent NSMenu instances.
@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }
}
```

- [ ] **Step 2: Verify the package builds**

Run:
```bash
swift build --product ClipboardApp 2>&1 | tail -10
```

Expected: `Build complete!` (no warnings or errors related to the new file).

- [ ] **Step 3: Run all tests to confirm no regression**

Run:
```bash
swift test 2>&1 | tail -15
```

Expected: all tests green.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClipboardApp/Appearance/AppearanceController.swift
git commit -m "feat(app): add AppearanceController to apply NSApp.appearance

@MainActor 包装一行 NSApp.appearance = mode.nsAppearance，给两个调用点
（启动 + 设置切换）使用。NSApp.appearance 同步广播至所有窗口和
后续 NSMenu，无需 NotificationCenter。"
```

---

## Task 4: Wire `AppearanceController` into `AppDelegate.applicationDidFinishLaunching`

**Files:**
- Modify: `Sources/ClipboardApp/App/AppDelegate.swift:30-36`

- [ ] **Step 1: Insert the apply call**

Locate `applicationDidFinishLaunching(_:)` in `Sources/ClipboardApp/App/AppDelegate.swift`. Currently:

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        services = AppServices()
        setupStatusBar()
        setupHotKey()
        checkFirstLaunch()
    }
```

Change to (insert one line **right after** `setActivationPolicy`):

```swift
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppearanceController.apply(ClipboardAppSettings.appearanceMode())
        services = AppServices()
        setupStatusBar()
        setupHotKey()
        checkFirstLaunch()
    }
```

> Why this position: applied **before** `setupStatusBar()` so the status bar's NSMenu inherits the right appearance from the first frame; applied **before** `checkFirstLaunch()` so the Welcome window also opens with correct appearance.

- [ ] **Step 2: Build the app target**

Run:
```bash
swift build --product ClipboardApp 2>&1 | tail -10
```

Expected: `Build complete!`.

- [ ] **Step 3: Smoke test — launch and quit**

Run:
```bash
Scripts/build-app-bundle.sh 2>&1 | tail -5
open .build/app-bundles/release/ClipboardApp.app
sleep 2
pgrep -lf ClipboardApp
osascript -e 'tell application "ClipboardApp" to quit'
```

Expected: pgrep shows the running process; quit succeeds without crash. (The `appearanceMode()` reads UserDefaults; with no key set, default `.system` applies — visually identical to current behavior.)

- [ ] **Step 4: Commit**

```bash
git add Sources/ClipboardApp/App/AppDelegate.swift
git commit -m "feat(app): apply AppearanceMode at applicationDidFinishLaunching

紧跟 setActivationPolicy 之后调用 AppearanceController.apply，
确保状态栏菜单和 Welcome 窗口从首帧起就携带正确外观。"
```

---

## Task 5: Add Settings UI Picker in `GeneralSettingsView`

**Files:**
- Modify: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift` (add `@AppStorage` for appearance, add Section as the first Section in `Form`, register `onChange` to call `AppearanceController.apply`)

- [ ] **Step 1: Add `@AppStorage` property and binding**

Open `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`. Locate the existing `@AppStorage` block (lines 8-18). Append a new `@AppStorage` after `returnCopiesOnly`:

```swift
    @AppStorage(ClipboardAppSettings.appearanceModeKey)
    private var appearanceModeRaw: String = AppearanceMode.system.rawValue
```

Then add a computed `Binding` after the existing `positionMode` binding (around line 23-28):

```swift
    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }
```

- [ ] **Step 2: Insert "外观" Section as the first Section in `Form`**

In the `body` property's `Form { ... }` block, insert a new Section **at the very top**, before the existing "辅助功能权限" Section:

```swift
        Form {
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

            Section("辅助功能权限") {
                // ... existing content unchanged
```

- [ ] **Step 3: Build to verify**

Run:
```bash
swift build --product ClipboardApp 2>&1 | tail -10
```

Expected: `Build complete!`.

- [ ] **Step 4: Run all tests — no regression**

Run:
```bash
swift test 2>&1 | tail -15
```

Expected: all tests green.

- [ ] **Step 5: Manual smoke test — open Settings and switch the picker**

Run:
```bash
Scripts/build-app-bundle.sh 2>&1 | tail -3
open .build/app-bundles/release/ClipboardApp.app
```

Then manually:
1. Click the menu bar icon → open Settings (or Cmd+Shift+V → ⚙️ button)
2. Verify "外观" Section appears at the top with a 3-segment Picker
3. Click "浅色" — Settings window should turn light immediately
4. Click "深色" — Settings window should turn dark immediately
5. Click "跟随系统" — Settings window matches current system theme
6. Quit app

Expected: each click changes the Settings window's appearance instantly without flicker or restart.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardApp/Settings/GeneralSettingsView.swift
git commit -m "feat(settings): add 外观 picker for appearance mode

在「设置 / 通用」最顶部新增「外观」Section，segmented Picker 提供
跟随系统/浅色/深色 三选一，onChange 立即调用
AppearanceController.apply，无需重启 app。"
```

---

## Task 6: Append manual acceptance entries to checklist

**Files:**
- Modify: `docs/manual-acceptance-checklist.md` (append a new `## 外观主题（v3 新增）` section at the end of file)

- [ ] **Step 1: Append the new section**

Open `docs/manual-acceptance-checklist.md`, scroll to the bottom (after the existing `## 设置窗口（v2 新增）` section). Append the content below verbatim (the outer 4-backtick fence is for this plan document's display only — copy only the inner content into the checklist file):

````markdown

## 外观主题（v3 新增）

设置 → 通用 → 外观 提供三选一 Picker：跟随系统 / 浅色 / 深色。验证下列 6 个组合：

| # | 系统外观 | App 设置 | 期望结果 |
|---|---|---|---|
| 1 | Light | 跟随系统 | QuickPanel / Settings / Welcome / 菜单栏下拉全为亮色 |
| 2 | Light | 浅色 | 同上 |
| 3 | Light | 深色 | 全部为暗色（不跟随系统） |
| 4 | Dark | 跟随系统 | 全部为暗色 |
| 5 | Dark | 浅色 | 全部为亮色（不跟随系统） |
| 6 | Dark | 深色 | 同 #4 |

切换系统外观命令（用于测试）：

```bash
# 切到亮色
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'

# 切到暗色
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
```

- [ ] 在「设置」窗口本身切换 Picker，整窗立即变色，**无需重启 app**
- [ ] 切换后立即按 Cmd+Shift+V 唤出 QuickPanel，颜色与设置一致
- [ ] 切换后右键点击菜单栏图标，下拉菜单颜色与设置一致
- [ ] 设置为「强制亮色」时关闭 app 重启，外观仍为亮色（持久化生效）
- [ ] 设置为「跟随系统」时切换系统外观，app 跟随变化
````

- [ ] **Step 2: Verify the file edit looks right**

Run:
```bash
tail -30 docs/manual-acceptance-checklist.md
```

Expected: the new section is at the end, properly formatted with the 6-row table and 5 checkboxes.

- [ ] **Step 3: Commit**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs(checklist): add appearance mode manual verification rows

6 个 (系统外观 × app 设置) 组合 + 5 项交互行为 checkbox。"
```

---

## Task 7: Final verification — full test suite + build + manual 6-combo

**Files:** none (verification only — no commit)

- [ ] **Step 1: Full test suite green**

Run:
```bash
swift test 2>&1 | tail -20
```

Expected: all three test targets (`ClipboardCoreTests`, `ClipboardPlatformTests`, `ClipboardAppTests`) pass with 0 failures. The new `ClipboardAppTests` reports 6 tests passing (3 from `AppearanceModeTests` + 3 from `ClipboardAppSettingsAppearanceTests`).

- [ ] **Step 2: Production bundle builds and signs**

Run:
```bash
Scripts/build-app-bundle.sh 2>&1 | tail -10
```

Expected: `Build of product 'ClipboardApp' complete!` followed by signing output ending in the bundle path.

- [ ] **Step 3: Manual 6-combo verification (per `docs/manual-acceptance-checklist.md` 外观主题 section)**

Walk through all 6 rows of the new checklist table. Sign off each row in the checklist file.

- [ ] **Step 4: Optional — verify no regression on existing manual checklist items**

Pick 2-3 high-value items from existing sections (e.g., 全局快捷键、快捷面板位置、欢迎窗口) and confirm they still behave correctly under the new appearance system.

---

## Done Criteria

- All 7 tasks above completed and committed
- `swift test` returns 0 failures across 3 targets
- `Scripts/build-app-bundle.sh` succeeds
- All 6 appearance-mode rows + 5 interaction checkboxes in `docs/manual-acceptance-checklist.md` signed off
- New files created: `Sources/ClipboardApp/Appearance/AppearanceController.swift`, `Tests/ClipboardAppTests/AppearanceModeTests.swift`, `Tests/ClipboardAppTests/ClipboardAppSettingsAppearanceTests.swift`
- Modified files: `Package.swift`, `Sources/ClipboardApp/AppSettings.swift`, `Sources/ClipboardApp/App/AppDelegate.swift`, `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`, `docs/manual-acceptance-checklist.md`
