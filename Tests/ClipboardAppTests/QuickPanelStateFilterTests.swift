import XCTest
@testable import ClipboardApp
@testable import ClipboardCore

@MainActor
final class QuickPanelStateFilterTests: XCTestCase {
  func testSelectItemUpdatesSelectedIndex() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectItem(at: 1)

    XCTAssertEqual(state.selectedIndex, 1)
  }

  func testSelectVisibleItemByNumberUsesOneBasedVisibleOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 2))
    _ = try await store.upsert(makePanelRecord(hash: "third", title: "Third", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    state.selectVisibleItem(number: 2)

    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Second")
  }

  func testSelectVisibleItemByNumberIgnoresOutOfRangeNumbers() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    state.selectVisibleItem(number: 9)

    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "First")
  }

  func testNumberSelectionFollowsFilteredVisibleOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "alpha-text", title: "Alpha Text", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "alpha-image", title: "Alpha Image", type: .image, lastCopiedAt: 2))
    _ = try await store.upsert(makePanelRecord(hash: "beta-text", title: "Beta Text", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    state.updateQuery("Alpha")
    await state.refresh()
    state.selectVisibleItem(number: 2)

    XCTAssertEqual(state.items.map(\.title), ["Alpha Text", "Alpha Image"])
    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Alpha Image")
  }

  func testPasteVisibleItemByNumberAutoPastesEvenWhenCopyOnlyWouldBeUsed() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pasteboard = AppTestPasteboardWriter()
    let poster = AppTestPasteEventPoster()
    let first = makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 2)
    let second = makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(first)
    _ = try await store.upsert(second)
    try await payloadStore.save(.text("first payload"), for: first.id)
    try await payloadStore.save(.text("second payload"), for: second.id)
    let state = makeState(store: store, payloadStore: payloadStore, pasteboard: pasteboard, eventPoster: poster)

    await state.refresh()
    await state.pasteVisibleItem(number: 2)

    XCTAssertEqual(pasteboard.lastText, "second payload")
    XCTAssertEqual(poster.postCount, 1)
    XCTAssertEqual(state.footerStatus, "Pasted text")
  }

  func testPastePlainTextUsesRichTextPlainText() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pasteboard = AppTestPasteboardWriter()
    let record = makePanelRecord(hash: "rich", title: "Rich", type: .richText, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.richText(plainText: "unstyled", rtfData: Data("{\\rtf1 styled}".utf8)), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)

    await state.refresh()
    await state.pastePlainText()

    XCTAssertEqual(pasteboard.lastText, "unstyled")
    XCTAssertEqual(state.footerStatus, "Pasted plain text")
  }

  func testPastePlainTextReportsUnsupportedFormatForImage() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "image", title: "Image", type: .image, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.image(data: Data([1, 2, 3]), uti: "public.png"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.pastePlainText()

    XCTAssertEqual(state.footerStatus, "Plain text paste is not supported for image")
  }

  func testSelectCurrentUsesMouseSelectedItem() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pasteboard = AppTestPasteboardWriter()
    let first = makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 1)
    let second = makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 2)
    _ = try await store.upsert(first)
    _ = try await store.upsert(second)
    try await payloadStore.save(.text("first payload"), for: first.id)
    try await payloadStore.save(.text("second payload"), for: second.id)
    let state = makeState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)

    await state.refresh()
    state.selectItem(at: 1)
    await state.selectCurrent(autoPaste: false)

    XCTAssertEqual(pasteboard.lastText, "first payload")
  }


  func testContentTypeFilterRefreshesVisibleItems() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "image", title: "Image", type: .image, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.updateContentFilter(.image)
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Image"])
  }

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

  func testAuthorizationFooterStatusSurvivesBackgroundRefresh() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    state.reportAutoPasteRequiresAccessibilityPermission()
    await state.refresh()

    XCTAssertEqual(state.footerStatus, "自动粘贴需要辅助功能权限，请在设置中授权")
  }

  func testAuthorizationReportShowsActionPromptUntilPresentationResets() async throws {
    let store = InMemoryHistoryStore()
    let state = makeState(store: store)

    state.reportAutoPasteRequiresAccessibilityPermission()

    XCTAssertEqual(state.actionPrompt, .autoPasteRequiresAccessibilityPermission)

    state.prepareForPresentation()

    XCTAssertNil(state.actionPrompt)
  }

  func testPrepareForPresentationAllowsRefreshStatusAgain() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    state.reportAutoPasteRequiresAccessibilityPermission()
    state.prepareForPresentation()
    await state.refresh()

    XCTAssertEqual(state.footerStatus, "1 item")
  }

  func testPrepareForPresentationCanSelectLatestRecordOnNextRefresh() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "older", title: "Older", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "newer", title: "Newer", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectItem(at: 1)
    state.prepareForPresentation(openSelectionBehavior: .latestRecord)
    await state.refresh()

    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items.first?.title, "Newer")
  }

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

  func testPrepareForPresentationCanPreservePreviousSelectionOnNextRefresh() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "older", title: "Older", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "newer", title: "Newer", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectItem(at: 1)
    state.prepareForPresentation(openSelectionBehavior: .previousSelection)
    await state.refresh()

    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Older")
  }

  func testPreviousSelectionFallbackUsesFirstHistoryItemWhenPreviousRecordDisappears() async throws {
    let store = InMemoryHistoryStore()
    let oldPinned = makePanelRecord(hash: "old-pinned", title: "Old Pinned", type: .text, lastCopiedAt: 4, isPinned: true)
    _ = try await store.upsert(oldPinned)
    _ = try await store.upsert(makePanelRecord(
      hash: "remaining-pinned",
      title: "Remaining Pinned",
      type: .text,
      lastCopiedAt: 3,
      isPinned: true
    ))
    _ = try await store.upsert(makePanelRecord(hash: "history", title: "History", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectItem(at: 0)
    _ = try await store.deleteRecord(id: oldPinned.id)
    state.prepareForPresentation(openSelectionBehavior: .previousSelection)
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Remaining Pinned", "History"])
    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "History")
  }

  func testUnchangedQueryDoesNotClearUserActionFooterStatus() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    state.reportAutoPasteRequiresAccessibilityPermission()
    state.updateQuery("")
    await state.refresh()

    XCTAssertEqual(state.footerStatus, "自动粘贴需要辅助功能权限，请在设置中授权")
  }

  func testChangingQueryClearsAuthorizationActionPrompt() async throws {
    let store = InMemoryHistoryStore()
    let state = makeState(store: store)

    state.reportAutoPasteRequiresAccessibilityPermission()
    state.updateQuery("new")

    XCTAssertNil(state.actionPrompt)
  }

  func testSuppressesNextQueryUpdateGeneratedByOptionShortcutCharacter() async throws {
    let store = InMemoryHistoryStore()
    let state = makeState(store: store)

    state.updateQuery("pay")
    state.suppressNextShortcutQueryMutation(insertedText: "π")
    state.updateQuery("payπ")

    XCTAssertEqual(state.query, "pay")
  }

  func testDeleteSelectedRefreshesItemsAndFooterStatus() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "older", title: "Older", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "newer", title: "Newer", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    await state.deleteSelected()

    XCTAssertEqual(state.items.map(\.title), ["Older"])
    XCTAssertEqual(state.footerStatus, "Deleted 1 item")
  }

  func testTogglePinnedUpdatesVisibleItemAndFooterStatus() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "item", title: "Item", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    await state.togglePinned()

    XCTAssertEqual(state.items.first?.title, "Item")
    XCTAssertEqual(state.items.first?.isPinned, true)
    XCTAssertEqual(state.footerStatus, "Pinned item")
  }

  func testTogglePinnedMovesSelectedItemToPinnedSectionAndKeepsItSelected() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "older", title: "Older", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "newer", title: "Newer", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()
    state.selectItem(at: 1)
    await state.togglePinned()

    XCTAssertEqual(state.items.map(\.title), ["Older", "Newer"])
    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.itemSections.first?.rows.map(\.record.title), ["Older"])
    XCTAssertEqual(state.footerStatus, "Pinned item")
  }

  func testItemRenderIdentityChangesWhenPinnedStateChanges() async throws {
    let store = InMemoryHistoryStore()
    let record = makePanelRecord(hash: "item", title: "Item", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    let state = makeState(store: store)

    await state.refresh()
    let before = state.itemRenderIdentities
    await state.togglePinned()
    let after = state.itemRenderIdentities

    XCTAssertEqual(before.map(\.recordID), after.map(\.recordID))
    XCTAssertNotEqual(before, after)
  }

  func testItemSectionsSeparatePinnedItemsFromHistory() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "newer", title: "Newer", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(
      hash: "pinned",
      title: "Pinned",
      type: .text,
      lastCopiedAt: 1,
      isPinned: true
    ))
    _ = try await store.upsert(makePanelRecord(hash: "middle", title: "Middle", type: .text, lastCopiedAt: 2))
    let state = makeState(store: store)

    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Pinned", "Newer", "Middle"])
    XCTAssertEqual(state.itemSections.map(\.title), ["Pinned", "History"])
    XCTAssertEqual(state.itemSections[0].rows.map(\.record.title), ["Pinned"])
    XCTAssertEqual(state.itemSections[0].rows.map(\.index), [0])
    XCTAssertEqual(state.itemSections[1].rows.map(\.record.title), ["Newer", "Middle"])
    XCTAssertEqual(state.itemSections[1].rows.map(\.index), [1, 2])
  }

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

  func testShowDetailPreviewLoadsSafeTextPayload() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.text("full text"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.title, "Text")
    XCTAssertEqual(state.detailPreview?.body, "full text")
    XCTAssertFalse(state.detailPreview?.isTruncated ?? true)
  }

  func testShowDetailPreviewKeepsLargeTextSummaryFirst() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let largeText = String(repeating: "a", count: 25_000)
    let record = makePanelRecord(hash: "large", title: "Large", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.text(largeText), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.body.count, 20_000)
    XCTAssertTrue(state.detailPreview?.isTruncated ?? false)
  }

  func testShowDetailPreviewUsesUniversalClipboardSourceName() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(
      hash: "universal",
      title: "Remote",
      type: .text,
      lastCopiedAt: 1,
      sourceAppName: "VS Code",
      sourceDeviceHint: .universalClipboard
    )
    _ = try await store.upsert(record)
    try await payloadStore.save(.text("remote text"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.source, "Universal Clipboard")
  }

  func testShowDetailPreviewUsesImageFallbackText() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "image", title: "Image title", type: .image, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.image(data: Data([1, 2, 3]), uti: "public.png"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.body, "Image title")
    XCTAssertFalse(state.detailPreview?.isTruncated ?? true)
  }

  func testShowDetailPreviewListsFileURLs() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "files", title: "Files", type: .file, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(
      .fileURLs([
        URL(fileURLWithPath: "/tmp/a.txt"),
        URL(fileURLWithPath: "/tmp/b.txt")
      ]),
      for: record.id
    )
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.body, "/tmp/a.txt\n/tmp/b.txt")
    XCTAssertFalse(state.detailPreview?.isTruncated ?? true)
  }

  func testShowDetailPreviewIgnoresStaleLoadAfterSelectionChanges() async throws {
    let store = InMemoryHistoryStore()
    let slowRecord = makePanelRecord(hash: "slow", title: "Slow", type: .text, lastCopiedAt: 2)
    let fastRecord = makePanelRecord(hash: "fast", title: "Fast", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(slowRecord)
    _ = try await store.upsert(fastRecord)

    let payloadStore = ControlledDelayPayloadStore(delayedRecordID: slowRecord.id)
    try await payloadStore.save(.text("slow text"), for: slowRecord.id)
    try await payloadStore.save(.text("fast text"), for: fastRecord.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    state.selectItem(at: 0)
    let slowLoad = Task { await state.showDetailPreview() }
    await payloadStore.waitForDelayedLoadToStart()
    state.selectItem(at: 1)
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.title, "Fast")

    await payloadStore.resumeDelayedLoad()
    await slowLoad.value

    XCTAssertEqual(state.detailPreview?.title, "Fast")
    XCTAssertEqual(state.detailPreview?.body, "fast text")
  }

  func testDismissDetailPreviewClearsPreview() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.text("full text"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()
    state.dismissDetailPreview()

    XCTAssertNil(state.detailPreview)
  }
}

@MainActor
private func makeState(
  store: InMemoryHistoryStore,
  payloadStore: any ClipboardPayloadStore = InMemoryPayloadStore(),
  pasteboard: AppTestPasteboardWriter = AppTestPasteboardWriter(),
  eventPoster: AppTestPasteEventPoster = AppTestPasteEventPoster(),
  mutationService: HistoryMutationService? = nil
) -> QuickPanelState {
  QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
    payloadStore: payloadStore,
    pasteController: PasteController(
      pasteboard: pasteboard,
      eventPoster: eventPoster
    ),
    mutationService: mutationService ?? HistoryMutationService(store: store, payloadStore: payloadStore)
  )
}

private func makePanelRecord(
  hash: String,
  title: String,
  type: ClipboardContentType,
  lastCopiedAt: TimeInterval,
  isPinned: Bool = false,
  sourceAppName: String? = "App",
  sourceDeviceHint: ClipboardSourceDeviceHint = .local,
  plainTextPreview: String? = nil
) -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: type,
    title: title,
    plainTextPreview: plainTextPreview ?? title,
    sourceAppBundleId: nil,
    sourceAppName: sourceAppName,
    sourceDeviceHint: sourceDeviceHint,
    createdAt: Date(timeIntervalSince1970: lastCopiedAt),
    lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: false,
    groupIds: [],
    retentionExempt: isPinned,
    metadata: nil,
    pasteboardTypes: []
  )
}

private actor ControlledDelayPayloadStore: ClipboardPayloadStore {
  private var payloadsByRecordID: [UUID: ClipboardPayload] = [:]
  private var delayedRecordID: UUID?
  private var delayedContinuation: CheckedContinuation<Void, Never>?
  private var loadStartedContinuations: [CheckedContinuation<Void, Never>] = []

  init(delayedRecordID: UUID) {
    self.delayedRecordID = delayedRecordID
  }

  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    payloadsByRecordID[recordID] = payload
  }

  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    if delayedRecordID == recordID {
      delayedRecordID = nil
      await withCheckedContinuation { continuation in
        delayedContinuation = continuation
        signalDelayedLoadStarted()
      }
    }

    return payloadsByRecordID[recordID]
  }

  func delete(for recordID: UUID) async throws {
    payloadsByRecordID.removeValue(forKey: recordID)
  }

  func waitForDelayedLoadToStart() async {
    if delayedContinuation != nil {
      return
    }

    await withCheckedContinuation { continuation in
      loadStartedContinuations.append(continuation)
    }
  }

  func resumeDelayedLoad() {
    delayedContinuation?.resume()
    delayedContinuation = nil
  }

  private func signalDelayedLoadStarted() {
    let continuations = loadStartedContinuations
    loadStartedContinuations.removeAll()
    continuations.forEach { $0.resume() }
  }
}

private final class AppTestPasteboardWriter: PasteboardWriting, @unchecked Sendable {
  private(set) var lastText: String?

  func write(payload: ClipboardPayload, marker: String) async -> Bool {
    if case let .text(text) = payload {
      lastText = text
    }
    return true
  }

  func containsMarker(_ marker: String) async -> Bool { true }
}

private final class AppTestPasteEventPoster: PasteEventPosting, @unchecked Sendable {
  private(set) var postCount = 0

  func isAccessibilityTrusted() -> Bool { true }

  func postCommandV() async -> Bool {
    postCount += 1
    return true
  }

  func postCommandV(marker: String, pasteboard: any PasteboardWriting) async -> PasteEventResult {
    postCount += 1
    return .posted
  }
}
