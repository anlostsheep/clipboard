# Maccy Core Parity Tab Cycling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add keyboard-first `Tab` and `Shift+Tab` cycling for QuickPanel content type filters as the first Maccy core parity enhancement.

**Architecture:** Keep the change inside existing QuickPanel boundaries. `QuickPanelKeyCaptureView` maps Tab keys to a filter-cycling action, `QuickPanelState` computes and applies the next `QuickPanelContentFilter`, and `QuickPanelView` wires the key action while preserving search focus.

**Tech Stack:** Swift 5.10, Swift Package Manager, SwiftUI, AppKit local key monitor, Carbon key codes, XCTest.

---

## Scope Check

The approved spec defines a broad core-parity target, but the implementation slice is intentionally narrow: Tab-based content type cycling in QuickPanel plus checklist coverage. OCR, Shortcuts, notifications, full Library Window browsing, and Maccy performance baseline automation remain outside this plan.

## File Structure

- Modify: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
  - Add keyboard mapping coverage for Tab, Shift+Tab, and modified Tab combinations.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
  - Add a `cycleContentFilter(Int)` keyboard action and callback.
- Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
  - Add state-level tests for filter cycling, query preservation, refresh behavior, and selection fallback.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
  - Add filter cycling logic and adjust refresh selection fallback when the previous selected record is no longer visible.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - Wire the new key action to `QuickPanelState` and keep the search field focused.
- Modify: `docs/manual-acceptance-checklist.md`
  - Add manual acceptance checks for Tab cycling.

## Task 1: Add QuickPanel Tab Key Mapping

**Files:**
- Modify: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`

- [ ] **Step 1: Write failing Tab key mapping tests**

Add these tests to `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`, after `testReturnAndKeypadEnterSubmitSelection`:

```swift
    func testTabCyclesContentFilterForward() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Tab),
            modifierFlags: []
        )

        XCTAssertEqual(action, .cycleContentFilter(1))
    }

    func testShiftTabCyclesContentFilterBackward() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Tab),
            modifierFlags: [.shift]
        )

        XCTAssertEqual(action, .cycleContentFilter(-1))
    }

    func testModifiedTabCombinationsAreNotCaptured() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.option]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.control]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.shift, .command]
            )
        )
    }
```

- [ ] **Step 2: Run the key mapping tests and verify failure**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

Expected: build fails because `QuickPanelKeyCaptureView.KeyboardAction` has no `.cycleContentFilter` case.

- [ ] **Step 3: Add the key action, callback, and Tab mapping**

Modify `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift` as follows.

Add the enum case:

```swift
  enum KeyboardAction: Equatable {
    case cancel
    case submit
    case move(Int)
    case focusSearch
    case openSettings
    case quit
    case deleteSelected
    case togglePinned
    case clearUnpinned
    case clearAll
    case cycleContentFilter(Int)
  }
```

Add a callback to the representable:

```swift
  let onCycleContentFilter: (Int) -> Void
```

Pass it into `Coordinator` in `makeCoordinator()`:

```swift
      onClearUnpinned: onClearUnpinned,
      onClearAll: onClearAll,
      onCycleContentFilter: onCycleContentFilter
```

Update `updateNSView`:

```swift
    context.coordinator.onClearUnpinned = onClearUnpinned
    context.coordinator.onClearAll = onClearAll
    context.coordinator.onCycleContentFilter = onCycleContentFilter
    context.coordinator.installMonitor()
```

Add the callback to `Coordinator`:

```swift
    var onCycleContentFilter: (Int) -> Void
```

Update the coordinator initializer signature and assignment:

```swift
      onClearUnpinned: @escaping () -> Void,
      onClearAll: @escaping () -> Void,
      onCycleContentFilter: @escaping (Int) -> Void
    ) {
      self.onMove = onMove
      self.onSubmit = onSubmit
      self.onCancel = onCancel
      self.onFocusSearch = onFocusSearch
      self.onOpenSettings = onOpenSettings
      self.onQuit = onQuit
      self.onDeleteSelected = onDeleteSelected
      self.onTogglePinned = onTogglePinned
      self.onClearUnpinned = onClearUnpinned
      self.onClearAll = onClearAll
      self.onCycleContentFilter = onCycleContentFilter
    }
```

Handle the new action in `Coordinator.handle(_:)`:

```swift
      case .cycleContentFilter(let delta):
        onCycleContentFilter(delta)
        return nil
```

Add Tab mapping near the top of `keyboardAction(keyCode:modifierFlags:)`, after `let modifiers = ...` and before destructive shortcut checks:

```swift
    if keyCode == UInt16(kVK_Tab) {
      if modifiers.isEmpty {
        return .cycleContentFilter(1)
      }
      if modifiers == [.shift] {
        return .cycleContentFilter(-1)
      }
      return nil
    }
```

- [ ] **Step 4: Run the key mapping tests and verify pass**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

Expected: `QuickPanelKeyCaptureTests` passes.

- [ ] **Step 5: Commit Task 1**

```bash
git add Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift
git commit -m "feat: map tab to quick panel filter cycling"
```

## Task 2: Add QuickPanel Filter Cycling State

**Files:**
- Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`

- [ ] **Step 1: Write failing state cycling tests**

Add these tests to `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`, after `testContentTypeFilterRefreshesVisibleItems`:

```swift
  func testCycleContentFilterMovesForwardWithWraparound() async throws {
    let store = InMemoryHistoryStore()
    let state = makeState(store: store)

    XCTAssertEqual(state.contentFilter, .all)

    state.cycleContentFilter(delta: 1)
    XCTAssertEqual(state.contentFilter, .text)

    state.cycleContentFilter(delta: 1)
    XCTAssertEqual(state.contentFilter, .link)

    state.cycleContentFilter(delta: 1)
    XCTAssertEqual(state.contentFilter, .image)

    state.cycleContentFilter(delta: 1)
    XCTAssertEqual(state.contentFilter, .file)

    state.cycleContentFilter(delta: 1)
    XCTAssertEqual(state.contentFilter, .all)
  }

  func testCycleContentFilterMovesBackwardWithWraparound() async throws {
    let store = InMemoryHistoryStore()
    let state = makeState(store: store)

    XCTAssertEqual(state.contentFilter, .all)

    state.cycleContentFilter(delta: -1)
    XCTAssertEqual(state.contentFilter, .file)

    state.cycleContentFilter(delta: -1)
    XCTAssertEqual(state.contentFilter, .image)

    state.cycleContentFilter(delta: -1)
    XCTAssertEqual(state.contentFilter, .link)

    state.cycleContentFilter(delta: -1)
    XCTAssertEqual(state.contentFilter, .text)

    state.cycleContentFilter(delta: -1)
    XCTAssertEqual(state.contentFilter, .all)
  }

  func testCycleContentFilterPreservesQueryAndRefreshesVisibleItems() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "alpha-text", title: "Alpha Text", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "alpha-image", title: "Alpha Image", type: .image, lastCopiedAt: 2))
    _ = try await store.upsert(makePanelRecord(hash: "beta-text", title: "Beta Text", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    state.updateQuery("Alpha")
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Alpha Text", "Alpha Image"])

    state.cycleContentFilter(delta: 1)
    await state.refresh()

    XCTAssertEqual(state.query, "Alpha")
    XCTAssertEqual(state.contentFilter, .text)
    XCTAssertEqual(state.items.map(\.title), ["Alpha Text"])
  }

  func testFilterRefreshSelectsFirstVisibleItemWhenPreviousSelectionDisappears() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "text-newer", title: "Text Newer", type: .text, lastCopiedAt: 4))
    _ = try await store.upsert(makePanelRecord(hash: "image", title: "Image", type: .image, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "text-older", title: "Text Older", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    XCTAssertEqual(state.items.map(\.title), ["Text Newer", "Image", "Text Older"])

    state.selectItem(at: 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Image")

    state.cycleContentFilter(delta: 1)
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Text Newer", "Text Older"])
    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Text Newer")
  }
```

- [ ] **Step 2: Run the state tests and verify failure**

Run:

```bash
swift test --filter QuickPanelStateFilterTests
```

Expected: build fails because `QuickPanelState` has no `cycleContentFilter(delta:)` method.

- [ ] **Step 3: Add filter advancement logic and state method**

Modify `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`.

Add this method inside `QuickPanelContentFilter`, after `contentTypes`:

```swift
  func advanced(by delta: Int) -> QuickPanelContentFilter {
    let filters = Self.allCases
    guard let currentIndex = filters.firstIndex(of: self), !filters.isEmpty else {
      return self
    }

    let count = filters.count
    let nextIndex = ((currentIndex + delta) % count + count) % count
    return filters[nextIndex]
  }
```

Add this method to `QuickPanelState`, after `updateContentFilter(_:)`:

```swift
  func cycleContentFilter(delta: Int) {
    updateContentFilter(contentFilter.advanced(by: delta))
  }
```

- [ ] **Step 4: Adjust selection fallback after filter refresh**

In `QuickPanelState.applyRefresh(querySnapshot:filterSnapshot:generation:)`, replace the `refreshedSelectedIndex` selection block:

```swift
    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex: Int
    if let selectionRecordID,
       let matchingIndex = refreshedItems.firstIndex(where: { $0.id == selectionRecordID }) {
      refreshedSelectedIndex = matchingIndex
      await viewModel.setSelection(index: matchingIndex)
    } else {
      refreshedSelectedIndex = await viewModel.selectedIndex
    }
```

with:

```swift
    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex: Int
    if let selectionRecordID,
       let matchingIndex = refreshedItems.firstIndex(where: { $0.id == selectionRecordID }) {
      refreshedSelectedIndex = matchingIndex
      await viewModel.setSelection(index: matchingIndex)
    } else if selectionRecordID != nil {
      refreshedSelectedIndex = 0
      await viewModel.setSelection(index: 0)
    } else {
      refreshedSelectedIndex = await viewModel.selectedIndex
    }
```

This keeps the previous selected record when it remains visible. If the previous selected record disappears under the new filter, selection falls back to the first visible item.

- [ ] **Step 5: Run the state tests and verify pass**

Run:

```bash
swift test --filter QuickPanelStateFilterTests
```

Expected: `QuickPanelStateFilterTests` passes.

- [ ] **Step 6: Commit Task 2**

```bash
git add Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift Sources/ClipboardApp/QuickPanel/QuickPanelState.swift
git commit -m "feat: cycle quick panel content filters"
```

## Task 3: Wire QuickPanel View And Acceptance Checklist

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Wire the cycle callback into QuickPanelView**

Modify `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`.

In the `QuickPanelKeyCaptureView(...)` initializer inside `private var keyCapture`, add this argument after `onClearAll`:

```swift
      onClearAll: {
        confirmsClearAll = true
        focusSearch()
      },
      onCycleContentFilter: { delta in
        state.cycleContentFilter(delta: delta)
        focusSearch()
      }
```

Do not change `shortcutHint` in this slice. The current footer is already dense; manual acceptance will validate the interaction without adding more visual text.

- [ ] **Step 2: Run QuickPanel compile-focused tests**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
swift test --filter QuickPanelStateFilterTests
```

Expected: both test groups pass. This catches initializer and callback wiring errors.

- [ ] **Step 3: Add manual acceptance checklist items**

Modify `docs/manual-acceptance-checklist.md`. In the `QuickPanel 快捷键` section, add these items after the existing item `QuickPanel 顶部类型过滤控件中的“类型”标签不换行、不挤压成两行`:

```markdown
- [ ] 打开 QuickPanel 且搜索框聚焦时，按 `Tab` 可将类型从 `All` 切到 `Text`
- [ ] 连续按 `Tab` 可按 `All → Text → Link → Image → File → All` 循环类型
- [ ] 按 `Shift+Tab` 可按反向顺序循环类型
- [ ] 输入搜索关键词后按 `Tab`，关键词不丢失，列表按“关键词 + 类型”共同过滤
- [ ] 中文输入法正在组词时，`Tab` 不破坏输入法 composition
- [ ] 切换类型后 QuickPanel 布局稳定，不出现 pinned/history 大空白回归
```

- [ ] **Step 4: Run docs whitespace check**

Run:

```bash
git diff --check -- Sources/ClipboardApp/QuickPanel/QuickPanelView.swift docs/manual-acceptance-checklist.md
```

Expected: no output.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelView.swift docs/manual-acceptance-checklist.md
git commit -m "docs: add tab filter cycling acceptance"
```

## Task 4: Final Verification And Stable Build

**Files:**
- Verify only; no source edits expected.

- [ ] **Step 1: Run QuickPanel targeted tests**

Run:

```bash
swift test --filter QuickPanel
```

Expected: all QuickPanel-related tests pass.

- [ ] **Step 2: Run full repository verification**

Run:

```bash
Scripts/verify.sh
```

Expected: all Core/App tests, Platform tests, `ClipboardApp` build, and `ClipboardManualProbe` build pass.

- [ ] **Step 3: Build a stable signed app bundle**

Run:

```bash
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
```

Expected output includes:

```text
signing with identity: 96C518DAFE2B21E278B4013FFCD988BF2FB236FE
.build/app-bundles/release/ClipboardApp.app
```

- [ ] **Step 4: Verify the app signature is not ad-hoc**

Run:

```bash
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

Expected output includes:

```text
Authority=ClipboardApp Local Code Signing
```

Expected output must not contain an ad-hoc authority.

- [ ] **Step 5: Perform manual acceptance**

Install or launch `.build/app-bundles/release/ClipboardApp.app`, then verify:

```text
1. Open QuickPanel and press Tab; type changes from All to Text.
2. Press Tab repeatedly; type cycles through Text, Link, Image, File, and back to All.
3. Press Shift+Tab; type cycles backward.
4. Type a query, press Tab, and confirm the query remains while the result list changes by type.
5. Start Chinese input method composition and confirm Tab does not break composition.
6. Confirm pinned/history spacing remains stable after cycling filters.
```

- [ ] **Step 6: Commit final verification notes if checklist changed after manual acceptance**

If manual acceptance updates `docs/manual-acceptance-checklist.md`, run:

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record tab filter cycling acceptance"
```

If no checklist status is updated during the implementation session, skip this commit.
