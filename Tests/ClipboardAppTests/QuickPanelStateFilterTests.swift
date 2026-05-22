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
}

@MainActor
private func makeState(
  store: InMemoryHistoryStore,
  payloadStore: InMemoryPayloadStore = InMemoryPayloadStore(),
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
  isPinned: Bool = false
) -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: type,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
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
