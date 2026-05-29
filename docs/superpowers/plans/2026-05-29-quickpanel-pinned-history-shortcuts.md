# QuickPanel 固定项/历史项快捷键分离 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留 QuickPanel pinned/history 分区，同时让打开时默认选中普通历史，并把 pinned 的 `Command+字母` 与 history 的 `Command+数字` 分离。

**Architecture:** 在 `QuickPanelState` 附近建立 section-local 快捷键模型，让 pinned/history 的行顺序、选中和 paste 解析都从同一个数据结构派生。`QuickPanelKeyCaptureView` 只负责把键盘事件转成 typed actions；`QuickPanelView` 只负责把 row shortcut badge 渲染出来。现有 storage、payload、paste transaction 和全局 QuickPanel hotkey 不变。

**Tech Stack:** Swift 5、SwiftUI、AppKit `NSEvent` local monitor、Carbon virtual key codes、XCTest、SwiftPM。

---

## File Structure

- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
  - Add `QuickPanelRowShortcut` and section-local shortcut assignment.
  - Change open-selection fallback to History-first.
  - Add History-local select/paste and Pinned-local select methods.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
  - Add pinned letter keyboard action.
  - Map `Command+A/S/D/F/G/H/J/K/L` to pinned slots.
  - Keep numeric shortcuts History-only through state/view wiring.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - Render `QuickPanelRowShortcut` badge labels instead of global numeric badges.
  - Wire numeric callbacks to History-local state methods.
  - Wire pinned letter callbacks to pinned-local state methods.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
  - Rename explicit number paste path to History-local behavior while preserving the external controller flow.
- Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
  - Add TDD coverage for History-first open selection, section-local shortcuts, and filtered shortcut reassignment.
  - Update existing numeric selection/paste expectations to History-local behavior.
- Modify: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
  - Add pinned letter key capture tests.
  - Update `Command+F` expectation because `Command+F` becomes the fourth pinned shortcut slot inside QuickPanel.
- Modify: `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift`
  - Update explicit number paste test names/fixtures to History-local semantics.
- Modify after user/manual verification: `docs/manual-acceptance-checklist.md`
  - Add a dated manual acceptance entry after a runnable build is verified.

---

### Task 1: Add Section-Local Row Shortcut Model

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

- [ ] **Step 1: Write failing tests for section-local shortcut assignment**

Append these tests inside `QuickPanelStateFilterTests` before `testShowDetailPreviewLoadsSafeTextPayload`:

```swift
  func testItemSectionsAssignPinnedLettersAndHistoryNumbersSeparately() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(
      hash: "pinned-a",
      title: "Pinned A",
      type: .text,
      lastCopiedAt: 1,
      isPinned: true
    ))
    _ = try await store.upsert(makePanelRecord(
      hash: "pinned-s",
      title: "Pinned S",
      type: .text,
      lastCopiedAt: 2,
      isPinned: true
    ))
    _ = try await store.upsert(makePanelRecord(hash: "history-1", title: "History 1", type: .text, lastCopiedAt: 4))
    _ = try await store.upsert(makePanelRecord(hash: "history-2", title: "History 2", type: .text, lastCopiedAt: 3))
    let state = makeState(store: store)

    await state.refresh()

    XCTAssertEqual(state.itemSections.map(\.kind), [.pinned, .history])
    XCTAssertEqual(state.itemSections[0].rows.map(\.record.title), ["Pinned S", "Pinned A"])
    XCTAssertEqual(state.itemSections[0].rows.map(\.shortcut?.label), ["⌘A", "⌘S"])
    XCTAssertEqual(state.itemSections[0].rows.map(\.shortcut?.accessibilityLabel), ["Shortcut Command A", "Shortcut Command S"])
    XCTAssertEqual(state.itemSections[1].rows.map(\.record.title), ["History 1", "History 2"])
    XCTAssertEqual(state.itemSections[1].rows.map(\.shortcut?.label), ["1", "2"])
    XCTAssertEqual(state.itemSections[1].rows.map(\.shortcut?.accessibilityLabel), ["Shortcut 1", "Shortcut 2"])
  }

  func testItemSectionsDoNotAssignHistoryNumberBeyondNine() async throws {
    let store = InMemoryHistoryStore()
    for index in 1...10 {
      _ = try await store.upsert(makePanelRecord(
        hash: "history-\(index)",
        title: "History \(index)",
        type: .text,
        lastCopiedAt: TimeInterval(20 - index)
      ))
    }
    let state = makeState(store: store)

    await state.refresh()

    let historyRows = try XCTUnwrap(state.itemSections.first { $0.kind == .history }?.rows)
    XCTAssertEqual(historyRows.map(\.shortcut?.label), ["1", "2", "3", "4", "5", "6", "7", "8", "9", nil])
  }

  func testItemSectionsDoNotAssignPinnedLetterBeyondLeftHandSlots() async throws {
    let store = InMemoryHistoryStore()
    for index in 1...10 {
      _ = try await store.upsert(makePanelRecord(
        hash: "pinned-\(index)",
        title: "Pinned \(index)",
        type: .text,
        lastCopiedAt: TimeInterval(index),
        isPinned: true
      ))
    }
    let state = makeState(store: store)

    await state.refresh()

    let pinnedRows = try XCTUnwrap(state.itemSections.first { $0.kind == .pinned }?.rows)
    XCTAssertEqual(pinnedRows.map(\.shortcut?.label), ["⌘A", "⌘S", "⌘D", "⌘F", "⌘G", "⌘H", "⌘J", "⌘K", "⌘L", nil])
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter QuickPanelStateFilterTests/testItemSectionsAssignPinnedLettersAndHistoryNumbersSeparately
```

Expected: FAIL because `QuickPanelItemRow` has no `shortcut` member.

- [ ] **Step 3: Implement row shortcut assignment**

In `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`, replace the existing `QuickPanelItemRow` and `QuickPanelItemSection` definitions with:

```swift
struct QuickPanelRowShortcut: Equatable {
  let label: String
  let accessibilityLabel: String

  static func historyNumber(_ number: Int) -> QuickPanelRowShortcut {
    QuickPanelRowShortcut(label: "\(number)", accessibilityLabel: "Shortcut \(number)")
  }

  static func pinnedLetter(_ letter: String) -> QuickPanelRowShortcut {
    QuickPanelRowShortcut(label: "⌘\(letter)", accessibilityLabel: "Shortcut Command \(letter)")
  }
}

struct QuickPanelItemRow: Identifiable, Equatable {
  let index: Int
  let record: ClipboardRecord
  let shortcut: QuickPanelRowShortcut?

  var id: UUID { record.id }
}

struct QuickPanelPlainTextPasteRequest {
  let record: ClipboardRecord
  let plainText: String
}

struct QuickPanelItemSection: Identifiable, Equatable {
  enum Kind: String {
    case pinned
    case history
  }

  static let pinnedShortcutLetters = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]

  let kind: Kind
  let title: String
  let rows: [QuickPanelItemRow]

  var id: Kind { kind }

  static func make(from items: [ClipboardRecord]) -> [QuickPanelItemSection] {
    let indexedItems = items.enumerated().map { index, record in
      (index: index, record: record)
    }
    let pinnedItems = indexedItems.filter { $0.record.isPinned }
    let historyItems = indexedItems.filter { !$0.record.isPinned }

    let pinnedRows = pinnedItems.enumerated().map { localIndex, item in
      QuickPanelItemRow(
        index: item.index,
        record: item.record,
        shortcut: pinnedShortcutLetters.indices.contains(localIndex)
          ? .pinnedLetter(pinnedShortcutLetters[localIndex])
          : nil
      )
    }
    let historyRows = historyItems.enumerated().map { localIndex, item in
      QuickPanelItemRow(
        index: item.index,
        record: item.record,
        shortcut: localIndex < 9 ? .historyNumber(localIndex + 1) : nil
      )
    }

    var sections: [QuickPanelItemSection] = []
    if !pinnedRows.isEmpty {
      sections.append(QuickPanelItemSection(kind: .pinned, title: "Pinned", rows: pinnedRows))
    }
    if !historyRows.isEmpty {
      sections.append(QuickPanelItemSection(kind: .history, title: "History", rows: historyRows))
    }
    return sections
  }
}
```

- [ ] **Step 4: Run section shortcut tests**

Run:

```bash
swift test --filter QuickPanelStateFilterTests/testItemSectionsAssignPinnedLettersAndHistoryNumbersSeparately
swift test --filter QuickPanelStateFilterTests/testItemSectionsDoNotAssignHistoryNumberBeyondNine
swift test --filter QuickPanelStateFilterTests/testItemSectionsDoNotAssignPinnedLetterBeyondLeftHandSlots
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift
git commit -m "feat: add quick panel section shortcuts"
```

---

### Task 2: Make Open Selection History-First

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

- [ ] **Step 1: Write failing tests for History-first open selection**

Append these tests near the existing `testPrepareForPresentationCanSelectLatestRecordOnNextRefresh` tests:

```swift
  func testPrepareForPresentationSelectsFirstHistoryItemWhenPinnedItemsExist() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(
      hash: "pinned",
      title: "Pinned",
      type: .text,
      lastCopiedAt: 1,
      isPinned: true
    ))
    _ = try await store.upsert(makePanelRecord(hash: "history-newer", title: "History Newer", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "history-older", title: "History Older", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    state.prepareForPresentation(openSelectionBehavior: .latestRecord)
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Pinned", "History Newer", "History Older"])
    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "History Newer")
  }

  func testPrepareForPresentationSelectsPinnedItemWhenOnlyPinnedItemsExist() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(
      hash: "pinned",
      title: "Pinned",
      type: .text,
      lastCopiedAt: 1,
      isPinned: true
    ))
    let state = makeState(store: store)

    state.prepareForPresentation(openSelectionBehavior: .latestRecord)
    await state.refresh()

    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Pinned")
  }

  func testPreviousSelectionFallbackUsesFirstHistoryItemWhenPreviousRecordDisappears() async throws {
    let store = InMemoryHistoryStore()
    let oldPinned = makePanelRecord(hash: "old-pinned", title: "Old Pinned", type: .text, lastCopiedAt: 1, isPinned: true)
    _ = try await store.upsert(oldPinned)
    _ = try await store.upsert(makePanelRecord(hash: "history", title: "History", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectItem(at: 0)
    try await store.delete(id: oldPinned.id)
    state.prepareForPresentation(openSelectionBehavior: .previousSelection)
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["History"])
    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "History")
  }
```

- [ ] **Step 2: Run tests to verify the mixed pinned/history case fails**

Run:

```bash
swift test --filter QuickPanelStateFilterTests/testPrepareForPresentationSelectsFirstHistoryItemWhenPinnedItemsExist
```

Expected: FAIL because current latest-record behavior selects index `0`, the pinned row.

- [ ] **Step 3: Implement History-first selection helpers**

In `QuickPanelState.prepareForPresentation`, replace the latest-record branch with:

```swift
    if openSelectionBehavior == .latestRecord {
      selectedIndex = defaultSelectionIndex(in: items)
      selectedRecordID = nil
    }
```

In `QuickPanelState.applyRefresh`, replace the block from `let selectionRecordID = selectedRecordID` through the `refreshedSelectedIndex` calculation with:

```swift
    let selectionRecordID = selectedRecordID
    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex: Int
    if pendingOpenSelectionBehavior == .latestRecord {
      refreshedSelectedIndex = defaultSelectionIndex(in: refreshedItems)
      await viewModel.setSelection(index: refreshedSelectedIndex)
    } else if let selectionRecordID,
              let matchingIndex = refreshedItems.firstIndex(where: { $0.id == selectionRecordID }) {
      refreshedSelectedIndex = matchingIndex
      await viewModel.setSelection(index: matchingIndex)
    } else if selectionRecordID != nil {
      refreshedSelectedIndex = defaultSelectionIndex(in: refreshedItems)
      await viewModel.setSelection(index: refreshedSelectedIndex)
    } else {
      refreshedSelectedIndex = await viewModel.selectedIndex
    }
```

Add this private helper inside `QuickPanelState`, near `currentRecordID`:

```swift
  private func defaultSelectionIndex(in records: [ClipboardRecord]) -> Int {
    records.firstIndex { !$0.isPinned } ?? (records.isEmpty ? 0 : 0)
  }
```

- [ ] **Step 4: Run open-selection tests**

Run:

```bash
swift test --filter QuickPanelStateFilterTests/testPrepareForPresentationSelectsFirstHistoryItemWhenPinnedItemsExist
swift test --filter QuickPanelStateFilterTests/testPrepareForPresentationSelectsPinnedItemWhenOnlyPinnedItemsExist
swift test --filter QuickPanelStateFilterTests/testPrepareForPresentationCanPreservePreviousSelectionOnNextRefresh
swift test --filter QuickPanelStateFilterTests/testPreviousSelectionFallbackUsesFirstHistoryItemWhenPreviousRecordDisappears
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift
git commit -m "feat: prefer history selection in quick panel"
```

---

### Task 3: Make State Numeric Shortcuts History-Local And Pinned Letters Select Pinned Rows

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

- [ ] **Step 1: Replace old numeric state tests with History-local tests**

In `QuickPanelStateFilterTests`, replace `testSelectVisibleItemByNumberUsesOneBasedVisibleOrder`, `testSelectVisibleItemByNumberIgnoresOutOfRangeNumbers`, `testNumberSelectionFollowsFilteredVisibleOrder`, and `testPasteVisibleItemByNumberAutoPastesEvenWhenCopyOnlyWouldBeUsed` with:

```swift
  func testSelectHistoryShortcutUsesHistoryLocalOrderAndSkipsPinnedRows() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(
      hash: "pinned",
      title: "Pinned",
      type: .text,
      lastCopiedAt: 1,
      isPinned: true
    ))
    _ = try await store.upsert(makePanelRecord(hash: "history-newer", title: "History Newer", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "history-older", title: "History Older", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectHistoryShortcut(number: 2)

    XCTAssertEqual(state.selectedIndex, 2)
    XCTAssertEqual(state.items[state.selectedIndex].title, "History Older")
  }

  func testSelectHistoryShortcutIgnoresOutOfRangeNumbers() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "history", title: "History", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    state.selectHistoryShortcut(number: 9)

    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "History")
  }

  func testHistoryShortcutSelectionFollowsFilteredHistoryOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "alpha-text", title: "Alpha Text", type: .text, lastCopiedAt: 4))
    _ = try await store.upsert(makePanelRecord(hash: "alpha-image", title: "Alpha Image", type: .image, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "beta-text", title: "Beta Text", type: .text, lastCopiedAt: 2))
    _ = try await store.upsert(makePanelRecord(hash: "alpha-pinned", title: "Alpha Pinned", type: .text, lastCopiedAt: 1, isPinned: true))
    let state = makeState(store: store)

    state.updateQuery("Alpha")
    await state.refresh()
    state.selectHistoryShortcut(number: 2)

    XCTAssertEqual(state.items.map(\.title), ["Alpha Pinned", "Alpha Text", "Alpha Image"])
    XCTAssertEqual(state.selectedIndex, 2)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Alpha Image")
  }

  func testPasteHistoryShortcutAutoPastesHistoryItemAndSkipsPinnedRows() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pasteboard = AppTestPasteboardWriter()
    let poster = AppTestPasteEventPoster()
    let pinned = makePanelRecord(hash: "pinned", title: "Pinned", type: .text, lastCopiedAt: 1, isPinned: true)
    let first = makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 3)
    let second = makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 2)
    _ = try await store.upsert(pinned)
    _ = try await store.upsert(first)
    _ = try await store.upsert(second)
    try await payloadStore.save(.text("pinned payload"), for: pinned.id)
    try await payloadStore.save(.text("first payload"), for: first.id)
    try await payloadStore.save(.text("second payload"), for: second.id)
    let state = makeState(store: store, payloadStore: payloadStore, pasteboard: pasteboard, eventPoster: poster)

    await state.refresh()
    await state.pasteHistoryShortcut(number: 2)

    XCTAssertEqual(pasteboard.lastText, "second payload")
    XCTAssertEqual(poster.postCount, 1)
    XCTAssertEqual(state.footerStatus, "Pasted text")
  }
```

Append pinned selection tests near these:

```swift
  func testSelectPinnedShortcutUsesPinnedLocalOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "history", title: "History", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "pinned-a", title: "Pinned A", type: .text, lastCopiedAt: 1, isPinned: true))
    _ = try await store.upsert(makePanelRecord(hash: "pinned-s", title: "Pinned S", type: .text, lastCopiedAt: 2, isPinned: true))
    let state = makeState(store: store)

    await state.refresh()
    state.selectPinnedShortcut(slot: 1)

    XCTAssertEqual(state.items.map(\.title), ["Pinned S", "Pinned A", "History"])
    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Pinned A")
  }

  func testSelectPinnedShortcutIgnoresOutOfRangeSlots() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "pinned", title: "Pinned", type: .text, lastCopiedAt: 1, isPinned: true))
    let state = makeState(store: store)

    await state.refresh()
    state.selectPinnedShortcut(slot: 8)

    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Pinned")
  }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter QuickPanelStateFilterTests/testSelectHistoryShortcutUsesHistoryLocalOrderAndSkipsPinnedRows
```

Expected: FAIL because `QuickPanelState` has no `selectHistoryShortcut(number:)`.

- [ ] **Step 3: Implement History-local and Pinned-local state methods**

In `QuickPanelState`, replace:

```swift
  func selectVisibleItem(number: Int) {
    let index = number - 1
    selectItem(at: index)
  }

  func hasVisibleItem(number: Int) -> Bool {
    items.indices.contains(number - 1)
  }

  func prepareVisibleItemPaste(number: Int) async -> Bool {
    if items.isEmpty || latestAppliedQuery != query || latestAppliedContentFilter != contentFilter {
      await refreshForUserAction()
    }

    guard hasVisibleItem(number: number) else {
      return false
    }

    selectVisibleItem(number: number)
    return true
  }
```

with:

```swift
  func selectHistoryShortcut(number: Int) {
    guard let index = historyShortcutIndex(number: number) else {
      return
    }
    selectItem(at: index)
  }

  func selectPinnedShortcut(slot: Int) {
    guard let index = pinnedShortcutIndex(slot: slot) else {
      return
    }
    selectItem(at: index)
  }

  func prepareHistoryShortcutPaste(number: Int) async -> Bool {
    if items.isEmpty || latestAppliedQuery != query || latestAppliedContentFilter != contentFilter {
      await refreshForUserAction()
    }

    guard let index = historyShortcutIndex(number: number) else {
      return false
    }

    selectItem(at: index)
    return true
  }
```

Replace:

```swift
  func pasteVisibleItem(number: Int) async {
    let index = number - 1
    guard items.indices.contains(index) else {
      return
    }

    selectItem(at: index)
    await selectCurrent(autoPaste: true)
  }
```

with:

```swift
  func pasteHistoryShortcut(number: Int) async {
    guard await prepareHistoryShortcutPaste(number: number) else {
      return
    }

    await selectCurrent(autoPaste: true)
  }
```

Add these private helpers near `currentRecordID`:

```swift
  private func historyShortcutIndex(number: Int) -> Int? {
    guard (1...9).contains(number) else {
      return nil
    }
    let historyRows = itemSections.first { $0.kind == .history }?.rows ?? []
    let localIndex = number - 1
    guard historyRows.indices.contains(localIndex) else {
      return nil
    }
    return historyRows[localIndex].index
  }

  private func pinnedShortcutIndex(slot: Int) -> Int? {
    guard QuickPanelItemSection.pinnedShortcutLetters.indices.contains(slot) else {
      return nil
    }
    let pinnedRows = itemSections.first { $0.kind == .pinned }?.rows ?? []
    guard pinnedRows.indices.contains(slot) else {
      return nil
    }
    return pinnedRows[slot].index
  }
```

- [ ] **Step 4: Run state shortcut tests**

Run:

```bash
swift test --filter QuickPanelStateFilterTests/testSelectHistoryShortcutUsesHistoryLocalOrderAndSkipsPinnedRows
swift test --filter QuickPanelStateFilterTests/testSelectHistoryShortcutIgnoresOutOfRangeNumbers
swift test --filter QuickPanelStateFilterTests/testHistoryShortcutSelectionFollowsFilteredHistoryOrder
swift test --filter QuickPanelStateFilterTests/testPasteHistoryShortcutAutoPastesHistoryItemAndSkipsPinnedRows
swift test --filter QuickPanelStateFilterTests/testSelectPinnedShortcutUsesPinnedLocalOrder
swift test --filter QuickPanelStateFilterTests/testSelectPinnedShortcutIgnoresOutOfRangeSlots
```

Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift
git commit -m "feat: split quick panel shortcut selection"
```

---

### Task 4: Capture Pinned Letter Shortcuts

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`

- [ ] **Step 1: Update key capture tests**

In `QuickPanelKeyCaptureTests`, replace `testCommandFRequestsSearchFocus` with:

```swift
    func testCommandFSelectsFourthPinnedShortcutInsideQuickPanel() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_ANSI_F),
            modifierFlags: [.command]
        )

        XCTAssertEqual(action, .selectPinnedShortcut(3))
    }
```

Append these tests near the existing number shortcut tests:

```swift
    func testCommandLettersSelectPinnedShortcutSlots() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.command]
            ),
            .selectPinnedShortcut(0)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_S),
                modifierFlags: [.command]
            ),
            .selectPinnedShortcut(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_L),
                modifierFlags: [.command]
            ),
            .selectPinnedShortcut(8)
        )
    }

    func testPinnedLetterShortcutsRequireExactCommandModifier() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: []
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.shift, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.control, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.option, .command]
            )
        )
    }

    func testCommandQAndCommandCommaKeepReservedQuickPanelActions() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Q),
                modifierFlags: [.command]
            ),
            .quit
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Comma),
                modifierFlags: [.command]
            ),
            .openSettings
        )
    }
```

- [ ] **Step 2: Run tests to verify pinned letter capture fails**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests/testCommandLettersSelectPinnedShortcutSlots
```

Expected: FAIL because `KeyboardAction` has no `selectPinnedShortcut`.

- [ ] **Step 3: Implement pinned letter keyboard action**

In `QuickPanelKeyCaptureView.KeyboardAction`, add:

```swift
    case selectPinnedShortcut(Int)
```

Add a callback property to `QuickPanelKeyCaptureView`:

```swift
  var onSelectPinnedShortcut: ((Int) -> Void)? = nil
```

Thread it through `makeCoordinator`, `updateNSView`, `Coordinator` stored properties, and `Coordinator.init` using the same pattern as `onSelectNumber`.

In the `switch action` block in `Coordinator.handle`, add:

```swift
      case .selectPinnedShortcut(let slot):
        guard let onSelectPinnedShortcut else {
          return event
        }
        onSelectPinnedShortcut(slot)
        return nil
```

In `keyboardAction(keyCode:shortcutModifiers:)`, insert this check after the number shortcut check and before `Command+F`/settings/quit mappings:

```swift
    if let pinnedSlot = pinnedShortcutSlot(for: keyCode), modifiers == [.command] {
      return .selectPinnedShortcut(pinnedSlot)
    }
```

Add this helper near `number(for:)`:

```swift
  private static func pinnedShortcutSlot(for keyCode: UInt16) -> Int? {
    switch keyCode {
    case UInt16(kVK_ANSI_A): return 0
    case UInt16(kVK_ANSI_S): return 1
    case UInt16(kVK_ANSI_D): return 2
    case UInt16(kVK_ANSI_F): return 3
    case UInt16(kVK_ANSI_G): return 4
    case UInt16(kVK_ANSI_H): return 5
    case UInt16(kVK_ANSI_J): return 6
    case UInt16(kVK_ANSI_K): return 7
    case UInt16(kVK_ANSI_L): return 8
    default: return nil
    }
  }
```

- [ ] **Step 4: Run key capture tests**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift
git commit -m "feat: capture quick panel pinned shortcuts"
```

---

### Task 5: Wire View And Controller To Section-Local Shortcuts

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift`

- [ ] **Step 1: Update controller tests to describe History-local paste**

In `QuickPanelControllerPresentationTests`, rename the number paste tests and update mixed fixture coverage by replacing `testPasteVisibleItemByNumberHidesPanelRestoresPreviousApplicationAndAutoPastes` with:

```swift
    func testPasteHistoryShortcutHidesPanelRestoresPreviousApplicationAndAutoPastesHistoryItem() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let eventPoster = PresentationTestPasteEventPoster()
        let pinned = makePresentationRecord(title: "Pinned", isPinned: true)
        let history = makePresentationRecord(title: "History")
        _ = try await store.upsert(pinned)
        _ = try await store.upsert(history)
        try await payloadStore.save(.text("pinned payload"), for: pinned.id)
        try await payloadStore.save(.text("history payload"), for: history.id)
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        var didRequestRestore = false
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            isAutoPasteAuthorized: { true },
            activatePreviousApplication: { _ in
                didRequestRestore = true
            }
        )

        controller.show()
        await state.refresh()
        controller.pasteHistoryShortcut(number: 1)
        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(pasteboard.lastText, "history payload")
        XCTAssertTrue(eventPoster.didPostCommandV)
        XCTAssertTrue(didRequestRestore)
        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "History shortcut paste should close the QuickPanel before posting Command+V to the previous app."
        )
    }
```

If `makePresentationRecord` does not yet accept `title` or `isPinned`, extend the helper at the bottom of `QuickPanelControllerPresentationTests` with parameters:

```swift
private func makePresentationRecord(
    title: String = "Presentation",
    type: ClipboardContentType = .text,
    isPinned: Bool = false
) -> ClipboardRecord {
    ClipboardRecord(
        id: UUID(),
        contentHash: title,
        primaryType: type,
        title: title,
        plainTextPreview: title,
        sourceAppBundleId: nil,
        sourceAppName: "App",
        sourceDeviceHint: .local,
        createdAt: Date(timeIntervalSince1970: 1),
        lastCopiedAt: Date(timeIntervalSince1970: isPinned ? 1 : 2),
        copyCount: 1,
        isPinned: isPinned,
        isFavorite: false,
        groupIds: [],
        retentionExempt: isPinned,
        metadata: nil,
        pasteboardTypes: []
    )
}
```

- [ ] **Step 2: Run controller test to verify it fails**

Run:

```bash
swift test --filter QuickPanelControllerPresentationTests/testPasteHistoryShortcutHidesPanelRestoresPreviousApplicationAndAutoPastesHistoryItem
```

Expected: FAIL because `QuickPanelController` has no `pasteHistoryShortcut(number:)`.

- [ ] **Step 3: Wire controller History-local paste**

In `QuickPanelController.makePanel`, change:

```swift
            onPasteNumber: { [weak self] number in self?.pasteVisibleItem(number: number) },
```

to:

```swift
            onPasteNumber: { [weak self] number in self?.pasteHistoryShortcut(number: number) },
```

Rename `func pasteVisibleItem(number: Int)` to:

```swift
    func pasteHistoryShortcut(number: Int) {
        guard isAutoPasteAuthorized() else {
            state.reportAutoPasteRequiresAccessibilityPermission()
            return
        }

        Task { @MainActor in
            guard await state.prepareHistoryShortcutPaste(number: number) else {
                return
            }

            let targetApplication = previousApplication
            hide()
            activatePreviousApplication(targetApplication)
            try? await Task.sleep(nanoseconds: 120_000_000)
            await state.pasteHistoryShortcut(number: number)
        }
    }
```

Update remaining controller tests to call `controller.pasteHistoryShortcut(number:)` and keep their assertions unchanged, except assertion messages should say "History shortcut paste".

- [ ] **Step 4: Wire QuickPanelView badge and callbacks**

In `QuickPanelView.rowView(_:)`, change the `QuickPanelRow` call from:

```swift
      numberShortcut: numberShortcut(for: row.index),
```

to:

```swift
      shortcut: shortcut(for: row),
```

Replace `private func numberShortcut(for index: Int) -> Int?` with:

```swift
  private func shortcut(for row: QuickPanelItemRow) -> QuickPanelRowShortcut? {
    guard numberShortcutMode != nil || row.record.isPinned else {
      return nil
    }

    return row.shortcut
  }
```

In the `keyCapture` wiring, change:

```swift
      onSelectNumber: { number in
        state.selectVisibleItem(number: number)
        focusSearch()
      },
```

to:

```swift
      onSelectNumber: { number in
        state.selectHistoryShortcut(number: number)
        focusSearch()
      },
```

Add pinned callback wiring:

```swift
      onSelectPinnedShortcut: { slot in
        state.selectPinnedShortcut(slot: slot)
        focusSearch()
      },
```

Place it next to `onSelectNumber`.

In `QuickPanelRow`, replace:

```swift
  let numberShortcut: Int?
```

with:

```swift
  let shortcut: QuickPanelRowShortcut?
```

Replace the trailing badge block:

```swift
      if let numberShortcut {
        QuickPanelNumberShortcutBadge(number: numberShortcut, isSelected: isSelected)
      } else if record.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
          .accessibilityLabel("Pinned")
      }
```

with:

```swift
      if let shortcut {
        QuickPanelShortcutBadge(shortcut: shortcut, isSelected: isSelected)
      } else if record.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
          .accessibilityLabel("Pinned")
      }
```

Rename `QuickPanelNumberShortcutBadge` to:

```swift
private struct QuickPanelShortcutBadge: View {
  let shortcut: QuickPanelRowShortcut
  let isSelected: Bool

  var body: some View {
    Text(shortcut.label)
      .font(.caption.weight(.bold))
      .monospacedDigit()
      .foregroundStyle(isSelected ? Color.accentColor : .secondary)
      .frame(minWidth: 22, minHeight: 22)
      .padding(.horizontal, shortcut.label.count > 1 ? 5 : 0)
      .background(
        Capsule()
          .fill(isSelected ? Color.white.opacity(0.92) : Color.secondary.opacity(0.16))
      )
      .accessibilityLabel(shortcut.accessibilityLabel)
  }
}
```

- [ ] **Step 5: Run view/controller related tests**

Run:

```bash
swift test --filter QuickPanelControllerPresentationTests
swift test --filter QuickPanelStateFilterTests
swift test --filter QuickPanelKeyCaptureTests
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelView.swift Sources/ClipboardApp/QuickPanel/QuickPanelController.swift Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift
git commit -m "feat: wire quick panel section shortcuts"
```

---

### Task 6: Run Full QuickPanel Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run aggregate QuickPanel tests**

Run:

```bash
swift test --filter QuickPanel
```

Expected: PASS.

- [ ] **Step 2: Run whitespace check for touched files**

Run:

```bash
git diff --check -- Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift Sources/ClipboardApp/QuickPanel/QuickPanelView.swift Sources/ClipboardApp/QuickPanel/QuickPanelController.swift Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift
```

Expected: no output.

- [ ] **Step 3: Commit any test-only fixes if needed**

If Step 1 or Step 2 required a test expectation or formatting fix, commit only touched QuickPanel files:

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift Sources/ClipboardApp/QuickPanel/QuickPanelView.swift Sources/ClipboardApp/QuickPanel/QuickPanelController.swift Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift
git commit -m "test: verify quick panel section shortcuts"
```

Expected: if no fixes were needed, skip this commit.

---

### Task 7: Manual Acceptance Documentation After App Verification

**Files:**
- Modify after user or local app verification: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Build or use a runnable app**

Use the repo's existing runnable path for this project. If implementation happens in this session, prefer the repo script if available:

```bash
Scripts/build-app-bundle.sh
```

Expected: a runnable app bundle is produced, or the command prints the exact signing/build prerequisite that must be handled before manual acceptance.

- [ ] **Step 2: Verify the UI behavior**

Manual checks:

```text
1. Prepare at least two pinned records and two normal history records.
2. Open QuickPanel.
3. Confirm pinned records remain visually above History.
4. Confirm the selected row is the first normal History row.
5. Press Command+1 and confirm the first normal History row is selected.
6. Press Command+2 and confirm the second normal History row is selected.
7. Press Command+A and confirm the first pinned row is selected.
8. Press Command+S and confirm the second pinned row is selected.
9. Search or switch type filter, then confirm History numbers and Pinned letters are recomputed within their visible sections.
10. Confirm Return, double-click, copy-only mode, and Option+Shift+Return still behave as before.
```

- [ ] **Step 3: Add dated acceptance entry**

Append this entry to `docs/manual-acceptance-checklist.md`, adjusting only the date and evidence line if the actual verification command differs:

```markdown
## QuickPanel 固定项/历史项快捷键分离验收记录（2026-05-29）

场景: QuickPanel 保留 Pinned/History 分区，同时默认选中普通 History，并分离 pinned 字母快捷键与 history 数字快捷键

验证:
  - `swift test --filter QuickPanel`
  - 用户或本地构建手工验证 QuickPanel 混合 pinned/history 场景

结果:
  - Pinned 仍展示在 History 上方。
  - 同时存在 pinned 和普通 history 时，打开 QuickPanel 默认选中第一条普通 History。
  - `Command+1...9` 只选择普通 History 的可见前 9 条。
  - `Control+Command+1...9` 只粘贴普通 History 的可见前 9 条。
  - `Command+A/S/D/F/G/H/J/K/L` 按可见顺序选择 pinned 项。
  - 搜索和类型过滤后，快捷键按过滤后的 section 局部顺序重新分配。
  - Return、双击、仅复制模式和无格式粘贴行为保持正常。

结论: PASS，QuickPanel 固定项/历史项快捷键分离完成验收。
```

- [ ] **Step 4: Commit acceptance documentation**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record quick panel shortcut acceptance"
```

---

## Self-Review

Spec coverage:

- 保留分区：Task 1 和 Task 5 保持 `QuickPanelItemSection` 的 `.pinned` / `.history` 渲染路径。
- 打开时默认选中普通 History：Task 2。
- `Command+1...9` 只作用于 History：Task 3、Task 5。
- `Control+Command+1...9` 只粘贴 History：Task 3、Task 5。
- `Command+A/S/D/F/G/H/J/K/L` 选择 pinned：Task 1、Task 3、Task 4、Task 5。
- 不做 `Command+0`：Task 1 和 Task 3 的 `1...9` / `0...8` 限制覆盖。
- 不做 pinned 直接粘贴：Task 4 只增加 `selectPinnedShortcut`，Task 5 只 wire select。
- 搜索/过滤后重算局部顺序：Task 1 和 Task 3 的 `itemSections` 派生路径覆盖，测试覆盖 filtered order。
- 手工验收记录：Task 7。

Placeholder scan:

- No placeholder markers, deferred implementation notes, or open-ended "add tests" steps.
- Each code-changing step includes concrete snippets and commands.

Type consistency:

- `QuickPanelRowShortcut` is defined before being used by `QuickPanelItemRow` and `QuickPanelShortcutBadge`.
- `selectHistoryShortcut(number:)`, `prepareHistoryShortcutPaste(number:)`, `pasteHistoryShortcut(number:)`, and `selectPinnedShortcut(slot:)` are introduced in Task 3 before view/controller wiring in Task 5.
- `selectPinnedShortcut(Int)` keyboard action and `onSelectPinnedShortcut` callback are introduced in Task 4 before view wiring in Task 5.
