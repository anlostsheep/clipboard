# macOS QuickPanel Copy-Only Return Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 QuickPanel 增加一个持久化勾选配置：勾选后 `Command+Shift+V` 呼出面板并按 `Return` 只把选中项写入系统剪贴板，不自动模拟 `Cmd+V`，用户需要再手动按一次 `Cmd+V` 才粘贴。

**Architecture:** 复用现有 `QuickPanelViewModel.selectedIntent(autoPaste:)` 和 `PasteController.paste(autoPaste:)`，因为 core 层已经支持 copy-only 行为。新增 App 层设置键并用 `@AppStorage` 暴露为主窗口复选框；QuickPanel 提交时读取同一个设置决定 `autoPaste`，QuickPanel footer 根据设置显示当前 `Return` 行为。

**Tech Stack:** Swift 5.10, SwiftUI `@AppStorage`, AppKit `NSPanel`, Swift Package Manager, XCTest, macOS 14+.

---

## Scope Check

This plan implements only the QuickPanel Return behavior preference.

In scope:

- Add a persistent checkbox setting for QuickPanel Return behavior.
- Default behavior remains current behavior: `Return` copies the selected payload and automatically posts `Cmd+V`.
- Checked behavior becomes copy-only: `Return` copies the selected payload to the system pasteboard and does not post `Cmd+V`.
- Keep QuickPanel close and target-app focus restore behavior unchanged, so after copy-only `Return` the user can immediately press `Cmd+V` in the target app.
- Update QuickPanel footer text to show whether `Return` means paste or copy.
- Add manual acceptance checks for default paste mode, copy-only mode, and persistence after restart.

Out of scope:

- A full Preferences window.
- Configurable global hotkey UI.
- Per-app paste behavior rules.
- Persistent clipboard history or payload storage.
- Changing `PasteController` semantics; it already supports `autoPaste: false`.
- Adding a second keyboard shortcut inside QuickPanel.

---

## File Structure

- Modify: `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`
  - Add one focused test proving `QuickPanelViewModel.selectedIntent(autoPaste: false)` preserves copy-only intent.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/AppSettings.swift`
  - Defines the `UserDefaults` key used by both the main window checkbox and QuickPanel submit path.
  - Exposes a small helper that converts the checkbox value into `autoPaste`.
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`
  - Adds an `@AppStorage` checkbox in the dashboard sidebar.
  - Keeps default unchecked so current auto-paste behavior remains unchanged.
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
  - Reads the setting at submit time and passes `autoPaste: false` when copy-only mode is enabled.
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - Reads the same setting and updates the footer shortcut hint.
- Modify: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`
  - Adds manual checks for both Return modes and setting persistence.

---

### Task 1: Cover Copy-Only Selection Intent

**Files:**
- Modify: `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`

- [ ] **Step 1: Add a regression test for copy-only intent**

In `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`, add this test after `testSelectedIntentUsesSelectedRecordIDAndAutoPasteFlag`:

```swift
  func testSelectedIntentCanRequestCopyOnlyMode() async throws {
    let store = InMemoryHistoryStore()
    let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
    _ = try await store.upsert(makeRecord(id: recordID, title: "copy only", lastCopiedAt: 1))

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "")

    let intent = await viewModel.selectedIntent(autoPaste: false)

    XCTAssertEqual(intent, QuickPanelSelectionIntent(recordID: recordID, autoPaste: false))
  }
```

- [ ] **Step 2: Run the focused test**

Run:

```bash
cd macos-clipboard-manager
swift test --filter QuickPanelViewModelTests/testSelectedIntentCanRequestCopyOnlyMode
```

Expected:

```text
Test Suite 'Selected tests' passed
```

This is expected to pass because `QuickPanelViewModel` already accepts an `autoPaste` flag. The test locks that behavior before wiring the UI setting.

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift
git commit -m "test: cover quick panel copy-only intent"
```

---

### Task 2: Add App-Level QuickPanel Setting Key

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/AppSettings.swift`

- [ ] **Step 1: Create `AppSettings.swift`**

Create `macos-clipboard-manager/Sources/ClipboardApp/AppSettings.swift`:

```swift
import Foundation

enum ClipboardAppSettings {
  static let quickPanelReturnCopiesOnlyKey = "quickPanel.returnCopiesOnly"

  static func quickPanelReturnCopiesOnly(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: quickPanelReturnCopiesOnlyKey)
  }

  static func quickPanelAutoPasteEnabled(defaults: UserDefaults = .standard) -> Bool {
    !quickPanelReturnCopiesOnly(defaults: defaults)
  }
}
```

- [ ] **Step 2: Build and verify the new app file compiles**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/AppSettings.swift
git commit -m "feat: add quick panel return setting"
```

---

### Task 3: Add the Dashboard Checkbox

**Files:**
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [ ] **Step 1: Add `@AppStorage` state to `ClipboardRootView`**

In `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`, add this property after `lastCaptureSummary`:

```swift
  @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
  private var quickPanelReturnCopiesOnly = false
```

The top of `ClipboardRootView` should become:

```swift
private struct ClipboardRootView: View {
  let services: AppServices
  @Environment(\.scenePhase) private var scenePhase
  @State private var isAuthorized = false
  @State private var isPollingClipboard = false
  @State private var status = "Checking accessibility"
  @State private var records: [ClipboardRecord] = []
  @State private var lastCaptureSummary = "No clipboard item captured in this session."
  @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
  private var quickPanelReturnCopiesOnly = false
  private let authorizationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let clipboardTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
```

- [ ] **Step 2: Add the checkbox to the dashboard sidebar**

In the dashboard sidebar, insert this block immediately after the `Recheck Accessibility` button:

```swift
        Divider()

        Toggle(isOn: $quickPanelReturnCopiesOnly) {
          Text("Return copies only")
        }
        .toggleStyle(.checkbox)

        Text("When enabled, QuickPanel Return copies the selected item. Press Command+V to paste it.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
```

The surrounding block should become:

```swift
        Button("Recheck Accessibility") {
          refreshAuthorization()
        }

        Divider()

        Toggle(isOn: $quickPanelReturnCopiesOnly) {
          Text("Return copies only")
        }
        .toggleStyle(.checkbox)

        Text("When enabled, QuickPanel Return copies the selected item. Press Command+V to paste it.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Spacer()
```

- [ ] **Step 3: Build and verify the dashboard compiles**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 4: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift
git commit -m "feat: add quick panel copy-only setting"
```

---

### Task 4: Wire the Setting Into QuickPanel Submit

**Files:**
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`

- [ ] **Step 1: Read the setting during submit**

In `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`, replace `submitSelection()`:

```swift
  private func submitSelection() {
    let targetApplication = previousApplication
    hide()

    if let targetApplication, !targetApplication.isTerminated {
      targetApplication.activate(options: [.activateAllWindows])
    }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 120_000_000)
      await state.selectCurrent(autoPaste: true)
    }
  }
```

with:

```swift
  private func submitSelection() {
    let targetApplication = previousApplication
    let autoPaste = ClipboardAppSettings.quickPanelAutoPasteEnabled()
    hide()

    if let targetApplication, !targetApplication.isTerminated {
      targetApplication.activate(options: [.activateAllWindows])
    }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 120_000_000)
      await state.selectCurrent(autoPaste: autoPaste)
    }
  }
```

This preserves the existing close-and-refocus flow. In copy-only mode, the target app is still active after `Return`, so the user's next manual `Command+V` goes to the original target.

- [ ] **Step 2: Build and verify submit wiring compiles**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift
git commit -m "feat: honor quick panel copy-only setting"
```

---

### Task 5: Update QuickPanel Footer Hint

**Files:**
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`

- [ ] **Step 1: Add `@AppStorage` to `QuickPanelView`**

In `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`, add this property after `sourceAppIconProvider`:

```swift
  @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
  private var quickPanelReturnCopiesOnly = false
```

The property block should become:

```swift
struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void
  let onSubmit: () -> Void
  @FocusState private var isSearchFocused: Bool
  @State private var sourceAppIconProvider = SourceAppIconProvider()
  @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
  private var quickPanelReturnCopiesOnly = false
```

- [ ] **Step 2: Add a computed footer hint**

Add this computed property above `footer`:

```swift
  private var shortcutHint: String {
    quickPanelReturnCopiesOnly ? "Return Copy  Cmd+V Paste  Esc Close" : "Return Paste  Esc Close"
  }
```

- [ ] **Step 3: Use the computed footer hint**

Inside `footer`, replace:

```swift
      Text("Return Paste  Esc Close")
        .foregroundStyle(.secondary)
```

with:

```swift
      Text(shortcutHint)
        .foregroundStyle(.secondary)
```

- [ ] **Step 4: Build and verify footer wiring compiles**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 5: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift
git commit -m "feat: show quick panel copy-only shortcut hint"
```

---

### Task 6: Update Manual Acceptance Checklist

**Files:**
- Modify: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Replace the existing auto-paste-only acceptance row**

In `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`, find:

```markdown
- [ ] 在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，记录被复制并自动粘贴
```

Replace it with:

```markdown
- [ ] 未勾选 `Return copies only` 时，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，记录被复制并自动粘贴
- [ ] 勾选 `Return copies only` 后，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，目标文本框不立即粘贴
- [ ] 勾选 `Return copies only` 后，`Return` 选择记录会把该记录写入系统剪贴板；随后手动按 `Command+V` 能粘贴该记录
- [ ] 重启 app 后，`Return copies only` 勾选状态保持不变
```

- [ ] **Step 2: Verify the QuickPanel section**

Run:

```bash
cd macos-clipboard-manager
sed -n '64,82p' Docs/manual-acceptance-checklist.md
```

Expected output includes these rows in the `## QuickPanel 快捷键` section:

```text
- [ ] 未勾选 `Return copies only` 时，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，记录被复制并自动粘贴
- [ ] 勾选 `Return copies only` 后，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，目标文本框不立即粘贴
- [ ] 勾选 `Return copies only` 后，`Return` 选择记录会把该记录写入系统剪贴板；随后手动按 `Command+V` 能粘贴该记录
- [ ] 重启 app 后，`Return copies only` 勾选状态保持不变
```

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Docs/manual-acceptance-checklist.md
git commit -m "docs: add quick panel copy-only acceptance checks"
```

---

### Task 7: Full Verification and App Bundle Smoke Test

**Files:**
- Read: `macos-clipboard-manager/Scripts/verify.sh`
- Read: `macos-clipboard-manager/Scripts/build-app-bundle.sh`
- Read: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Run automated verification**

Run:

```bash
cd macos-clipboard-manager
Scripts/verify.sh
```

Expected:

```text
Test Suite 'All tests' passed
Build of product 'ClipboardApp' complete!
Build of product 'ClipboardManualProbe' complete!
```

- [ ] **Step 2: Build the app bundle**

Run:

```bash
cd macos-clipboard-manager
CODE_SIGN_IDENTITY='-' Scripts/build-app-bundle.sh
```

Expected:

```text
warning: using ad-hoc signing; macOS Accessibility permission may need to be re-granted after code changes
/Users/lostsheep/programing/projects/agent-learning-skills/macos-clipboard-manager/.build/app-bundles/release/ClipboardApp.app
```

Use `CODE_SIGN_IDENTITY='-'` because the local `ClipboardApp Local Code Signing` identity can block in non-interactive shell sessions.

- [ ] **Step 3: Launch the app bundle**

Run:

```bash
cd macos-clipboard-manager
pkill -f "ClipboardApp.app/Contents/MacOS/ClipboardApp" || true
open -n .build/app-bundles/release/ClipboardApp.app
```

Expected:

```text
Clipboard app launches.
If Accessibility permission is no longer trusted because of ad-hoc signing, the permission gate appears and can be re-authorized.
```

- [ ] **Step 4: Manual default-mode acceptance**

Perform these manual actions:

```text
1. Ensure `Return copies only` is unchecked.
2. Focus a normal text field in another app.
3. Press Command+Shift+V.
4. Select a clipboard item with Up/Down.
5. Press Return.
```

Expected:

```text
The selected item is written to the system clipboard and automatically pasted into the target text field.
QuickPanel footer shows `Return Paste  Esc Close`.
```

- [ ] **Step 5: Manual copy-only acceptance**

Perform these manual actions:

```text
1. Check `Return copies only` in the Clipboard main window.
2. Focus a normal text field in another app.
3. Press Command+Shift+V.
4. Select a clipboard item with Up/Down.
5. Press Return.
6. Confirm the target text field does not change immediately.
7. Press Command+V manually.
```

Expected:

```text
Return closes QuickPanel and writes the selected item to the system clipboard without automatic paste.
The manual Command+V then pastes the selected item into the target text field.
QuickPanel footer shows `Return Copy  Cmd+V Paste  Esc Close`.
```

- [ ] **Step 6: Manual persistence acceptance**

Perform these manual actions:

```text
1. Leave `Return copies only` checked.
2. Quit Clipboard app.
3. Launch Clipboard app again.
```

Expected:

```text
The `Return copies only` checkbox remains checked.
Command+Shift+V QuickPanel still uses copy-only Return behavior.
```

- [ ] **Step 7: Confirm working tree**

Run:

```bash
git status --short --branch --untracked-files=all
```

Expected:

```text
Only unrelated pre-existing local files remain modified or untracked.
```

---

## Self-Review

- Spec coverage: This plan covers the requested checkbox configuration, default auto-paste behavior preservation, checked copy-only behavior, manual `Command+V` follow-up, footer hint, persistence, tests, and manual acceptance.
- Deliberate gaps: No full Preferences window, no configurable hotkey UI, no per-app rule system, and no clipboard persistence changes.
- Type consistency: The plan uses existing `QuickPanelViewModel.selectedIntent(autoPaste:)`, `QuickPanelState.selectCurrent(autoPaste:)`, and `PasteController.paste(autoPaste:)` flow, with a new App-only `ClipboardAppSettings` helper.
- Verification: The plan includes a focused XCTest for copy-only intent, repeated `swift build --product ClipboardApp`, full `Scripts/verify.sh`, ad-hoc app bundle build, launch smoke test, and manual QuickPanel acceptance checks.
