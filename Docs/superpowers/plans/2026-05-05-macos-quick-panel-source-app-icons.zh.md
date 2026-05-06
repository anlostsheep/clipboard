# macOS QuickPanel Source App Icons Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 QuickPanel 历史列表中用来源 App 的真实 macOS 图标替代纯内容类型图标，让用户一眼识别剪贴板内容来自 Chrome、VS Code、Terminal 等应用。

**Architecture:** 保持 `ClipboardCore` 不依赖 AppKit，不把图标写进 `ClipboardRecord`。在 `ClipboardApp` 目标内新增一个 AppKit-only 的图标解析和内存缓存组件，QuickPanel 行渲染时根据 `ClipboardRecord.sourceAppBundleId` 取 `NSImage`，找不到来源应用时回退到当前 SF Symbol 内容类型图标。

**Tech Stack:** Swift 5.10, SwiftUI, AppKit `NSWorkspace`, Swift Package Manager, macOS 14+.

---

## Scope Check

This plan implements only the visible source-app icon enhancement in the QuickPanel list.

In scope:

- Resolve source application icons from `ClipboardRecord.sourceAppBundleId`.
- Cache resolved `NSImage` instances in memory for the current app session.
- Render source app icon in `QuickPanelRow`.
- Keep source app name text visible as secondary metadata.
- Fall back to the existing content-type SF Symbol when source app icon cannot be resolved.
- Add a manual acceptance checklist row for source app icons.

Out of scope:

- Persisting icon images to disk.
- Adding icon fields to `ClipboardRecord`.
- Changing `ClipboardCore`, `ClipboardPlatform`, or pasteboard capture logic.
- Building a thumbnail cache for clipboard payload previews.
- Supporting imported historical records without a bundle id beyond fallback behavior.

---

## File Structure

- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/SourceAppIconProvider.swift`
  - App-only source app icon resolver and in-memory cache.
  - Uses `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`.
  - Returns `nil` when a record has no bundle id or the app cannot be resolved.
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - Owns one `SourceAppIconProvider` for the panel view.
  - Passes the resolved `NSImage?` into `QuickPanelRow`.
  - Renders `Image(nsImage:)` when available; otherwise keeps current SF Symbol fallback.
- Modify: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`
  - Adds one QuickPanel checklist row for source app icon display and fallback.

---

### Task 1: Add Source App Icon Provider

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/SourceAppIconProvider.swift`

- [ ] **Step 1: Create the provider file**

Create `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/SourceAppIconProvider.swift`:

```swift
import AppKit
import ClipboardCore

@MainActor
final class SourceAppIconProvider {
  private let iconSize = NSSize(width: 24, height: 24)
  private var iconsByBundleID: [String: NSImage] = [:]

  func icon(for record: ClipboardRecord) -> NSImage? {
    guard let bundleID = record.sourceAppBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !bundleID.isEmpty
    else {
      return nil
    }

    if let cachedIcon = iconsByBundleID[bundleID] {
      return cachedIcon
    }

    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return nil
    }

    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
    icon.size = iconSize
    iconsByBundleID[bundleID] = icon
    return icon
  }
}
```

- [ ] **Step 2: Build and verify the new file compiles**

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
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/SourceAppIconProvider.swift
git commit -m "feat: add source app icon provider"
```

---

### Task 2: Render Source App Icons in QuickPanel Rows

**Files:**
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`

- [ ] **Step 1: Import AppKit and add a provider to `QuickPanelView`**

Modify the top of `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift` to import AppKit and add one provider property:

```swift
import AppKit
import ClipboardCore
import SwiftUI

struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void
  let onSubmit: () -> Void
  @FocusState private var isSearchFocused: Bool
  @State private var sourceAppIconProvider = SourceAppIconProvider()
```

`@State` keeps the provider instance stable across SwiftUI view updates so the in-memory icon cache is not recreated during normal panel redraws.

- [ ] **Step 2: Pass resolved icons into `QuickPanelRow`**

In `QuickPanelView.results`, replace the current row construction:

```swift
QuickPanelRow(record: record, isSelected: index == state.selectedIndex)
  .id(record.id)
  .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
```

with:

```swift
QuickPanelRow(
  record: record,
  isSelected: index == state.selectedIndex,
  sourceIcon: sourceAppIconProvider.icon(for: record)
)
.id(record.id)
.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
```

- [ ] **Step 3: Extend `QuickPanelRow` to accept a source icon**

Replace the `QuickPanelRow` declaration:

```swift
private struct QuickPanelRow: View {
  let record: ClipboardRecord
  let isSelected: Bool
```

with:

```swift
private struct QuickPanelRow: View {
  let record: ClipboardRecord
  let isSelected: Bool
  let sourceIcon: NSImage?
```

- [ ] **Step 4: Replace the left icon rendering with source icon support**

Inside `QuickPanelRow.body`, replace:

```swift
Image(systemName: iconName)
  .frame(width: 22)
  .foregroundStyle(isSelected ? .white : .cyan)
```

with:

```swift
SourceIconView(
  sourceIcon: sourceIcon,
  fallbackSymbolName: iconName,
  isSelected: isSelected
)
```

- [ ] **Step 5: Add the `SourceIconView` helper**

Add this helper below `QuickPanelRow` in `QuickPanelView.swift`:

```swift
private struct SourceIconView: View {
  let sourceIcon: NSImage?
  let fallbackSymbolName: String
  let isSelected: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.12))

      if let sourceIcon {
        Image(nsImage: sourceIcon)
          .resizable()
          .scaledToFit()
          .frame(width: 22, height: 22)
          .clipShape(RoundedRectangle(cornerRadius: 5))
      } else {
        Image(systemName: fallbackSymbolName)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(isSelected ? .white : .cyan)
      }
    }
    .frame(width: 30, height: 30)
    .accessibilityHidden(true)
  }
}
```

- [ ] **Step 6: Build and verify**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 7: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift
git commit -m "feat: show source app icons in quick panel"
```

---

### Task 3: Add Source Icon Manual Acceptance Check

**Files:**
- Modify: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Add the manual acceptance row**

In `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`, find the `## QuickPanel 快捷键` section and add this row after the item that says QuickPanel shows recent session history:

```markdown
- [ ] QuickPanel 每行左侧显示来源 App 图标；无法识别来源 App 时回退为内容类型图标
```

The section should include these adjacent rows:

```markdown
- [ ] QuickPanel 首屏显示最近复制的 session 历史，最新记录排在最上方
- [ ] QuickPanel 每行左侧显示来源 App 图标；无法识别来源 App 时回退为内容类型图标
- [ ] 输入搜索关键词后，列表只保留匹配标题、摘要或来源 App 的记录
```

- [ ] **Step 2: Commit**

```bash
git add macos-clipboard-manager/Docs/manual-acceptance-checklist.md
git commit -m "docs: add source app icon acceptance check"
```

---

### Task 4: Full Verification and App Bundle Smoke Test

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
```

- [ ] **Step 2: Build and launch the signed app bundle**

Run:

```bash
cd macos-clipboard-manager
pkill -f "ClipboardApp.app/Contents/MacOS/ClipboardApp" || true
app_path="$(Scripts/build-app-bundle.sh)"
open -n "$app_path"
```

Expected:

```text
signing with identity: ClipboardApp Local Code Signing
```

- [ ] **Step 3: Populate clipboard history from multiple apps**

Perform these manual setup actions:

```text
1. Copy one text snippet from Google Chrome.
2. Copy one text snippet from VS Code.
3. Copy one text snippet from Terminal or Ghostty.
4. Press Command+Shift+V to open QuickPanel.
```

Expected:

```text
QuickPanel opens and shows rows whose left icons match the source apps where bundle ids are available.
Rows without a resolvable bundle id use the content-type fallback icon.
```

- [ ] **Step 4: Verify search still works**

Perform these manual actions:

```text
1. With QuickPanel open, type a keyword from the Chrome copied text.
2. Confirm the matching row remains visible.
3. Press Escape.
```

Expected:

```text
The search field receives text immediately, filtering still works, and Escape closes the panel.
```

- [ ] **Step 5: Confirm working tree**

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

- Spec coverage: This plan covers source app icon resolution, row rendering, fallback behavior, manual acceptance, full verification, and app bundle smoke testing.
- Deliberate gaps: No persistent icon cache, no `ClipboardRecord` schema change, and no payload thumbnail work.
- Type consistency: `SourceAppIconProvider.icon(for:)` returns `NSImage?`, and `QuickPanelRow` receives that value as `sourceIcon: NSImage?`.
- Verification: The plan uses `swift build --product ClipboardApp`, `Scripts/verify.sh`, signed app bundle launch, and manual multi-app icon checks.
