import XCTest
@testable import ClipboardCore

final class QuickPanelViewModelTests: XCTestCase {
  func testRefreshLoadsLightweightRecords() async throws {
    let store = InMemoryHistoryStore()
    let record = ClipboardRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
      contentHash: "hash",
      primaryType: .text,
      title: "hello",
      plainTextPreview: "hello",
      sourceAppBundleId: nil,
      sourceAppName: "Terminal",
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
    _ = try await store.upsert(record)

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "hel")
    let titles = await viewModel.items.map(\.title)

    XCTAssertEqual(titles, ["hello"])
  }

  func testSelectedIntentUsesSelectedRecordIDAndAutoPasteFlag() async throws {
    let store = InMemoryHistoryStore()
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
    _ = try await store.upsert(makeRecord(id: firstID, title: "older", lastCopiedAt: 1))
    _ = try await store.upsert(makeRecord(id: secondID, title: "newer", lastCopiedAt: 2))

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "")
    await viewModel.moveSelection(delta: 1)

    let intent = await viewModel.selectedIntent(autoPaste: true)

    XCTAssertEqual(intent, QuickPanelSelectionIntent(recordID: firstID, autoPaste: true))
  }

  func testSelectedIntentCanRequestCopyOnlyMode() async throws {
    let store = InMemoryHistoryStore()
    let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000023")!
    _ = try await store.upsert(makeRecord(id: recordID, title: "copy only", lastCopiedAt: 1))

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "")

    let intent = await viewModel.selectedIntent(autoPaste: false)

    XCTAssertEqual(intent, QuickPanelSelectionIntent(recordID: recordID, autoPaste: false))
  }

  func testRefreshCanFilterByContentTypeAndGroup() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000024")!,
      title: "text work",
      primaryType: .text,
      lastCopiedAt: 1,
      groupIds: ["work"]
    ))
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000025")!,
      title: "link work",
      primaryType: .link,
      lastCopiedAt: 2,
      groupIds: ["work"]
    ))
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000026")!,
      title: "link home",
      primaryType: .link,
      lastCopiedAt: 3,
      groupIds: ["home"]
    ))

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "", contentTypes: [.link], groupIDs: ["work"])
    let titles = await viewModel.items.map(\.title)

    XCTAssertEqual(titles, ["link work"])
  }

  func testRefreshSortsPinnedItemsBeforeRecentHistory() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000027")!,
      title: "newer unpinned",
      lastCopiedAt: 3
    ))
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000028")!,
      title: "older pinned",
      lastCopiedAt: 1,
      isPinned: true
    ))
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000029")!,
      title: "middle unpinned",
      lastCopiedAt: 2
    ))

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "")
    let titles = await viewModel.items.map(\.title)

    XCTAssertEqual(titles, ["older pinned", "newer unpinned", "middle unpinned"])
  }

  func testRefreshSortsPinnedItemsByPinnedAtDescending() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
      title: "copied newer pinned earlier",
      lastCopiedAt: 30,
      isPinned: true,
      pinnedAt: 5
    ))
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
      title: "copied older pinned later",
      lastCopiedAt: 10,
      isPinned: true,
      pinnedAt: 20
    ))
    _ = try await store.upsert(makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000032")!,
      title: "newest unpinned",
      lastCopiedAt: 40
    ))

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "")
    let titles = await viewModel.items.map(\.title)

    XCTAssertEqual(titles, [
      "copied older pinned later",
      "copied newer pinned earlier",
      "newest unpinned"
    ])
  }

  func testRefreshPreservesRecentHistoryWhenPinnedItemsExceedPageLimit() async throws {
    let store = InMemoryHistoryStore()
    for index in 0..<12 {
      _ = try await store.upsert(makeRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000001\(String(format: "%02d", index))")!,
        title: "pinned \(index)",
        lastCopiedAt: TimeInterval(100 + index),
        isPinned: true,
        pinnedAt: TimeInterval(100 + index)
      ))
    }
    for index in 0..<6 {
      _ = try await store.upsert(makeRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000002\(String(format: "%02d", index))")!,
        title: "history \(index)",
        lastCopiedAt: TimeInterval(200 + index)
      ))
    }

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 10)
    await viewModel.refresh(query: "")
    let items = await viewModel.items

    XCTAssertEqual(items.count, 10)
    XCTAssertEqual(items.filter(\.isPinned).map(\.title), [
      "pinned 11",
      "pinned 10",
      "pinned 9",
      "pinned 8",
      "pinned 7"
    ])
    XCTAssertEqual(items.filter { !$0.isPinned }.map(\.title), [
      "history 5",
      "history 4",
      "history 3",
      "history 2",
      "history 1"
    ])
  }

  private func makeRecord(
    id: UUID,
    title: String,
    primaryType: ClipboardContentType = .text,
    lastCopiedAt: TimeInterval,
    groupIds: [String] = [],
    isPinned: Bool = false,
    pinnedAt: TimeInterval? = nil,
    sourceAppName: String = "Terminal",
    createdAt: TimeInterval = 1,
    copyCount: Int = 1
  ) -> ClipboardRecord {
    ClipboardRecord(
      id: id,
      contentHash: title,
      primaryType: primaryType,
      title: title,
      plainTextPreview: title,
      sourceAppBundleId: nil,
      sourceAppName: sourceAppName,
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: createdAt),
      lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
      copyCount: copyCount,
      isPinned: isPinned,
      pinnedAt: pinnedAt.map(Date.init(timeIntervalSince1970:)),
      isFavorite: false,
      groupIds: groupIds,
      retentionExempt: isPinned,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
  }

  func testFuzzyQueryMatchesNonContiguousCharacters() async throws {
    // "cbm" is not a substring of either title, but is an in-order
    // subsequence of "clipboard manager" only.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "clipboard manager", lastCopiedAt: 1))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "unrelated", lastCopiedAt: 2))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "cbm")

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["clipboard manager"])
  }

  func testSubstringMatchRanksAboveSubsequenceMatch() async throws {
    // "clip" is a substring of "my clip notes" but only a scattered
    // subsequence of "cool lion iron plate". The substring hit must rank
    // first even though the subsequence record is more recent.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "my clip notes", lastCopiedAt: 100))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "cool lion iron plate", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "clip")

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles.first, "my clip notes")
  }

  func testSearchMatchesExposesPrimaryTextOffsets() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "clipboard", lastCopiedAt: 1))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "board")

    let items = await viewModel.items
    let matches = await viewModel.searchMatches
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(matches[items[0].id]?.primaryTextOffsets, [4, 5, 6, 7, 8])
  }

  func testEmptyQueryClearsSearchMatchesAndKeepsRecencyOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "older", lastCopiedAt: 100))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "newer", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "old")
    await viewModel.refresh(query: "")

    let matches = await viewModel.searchMatches
    let titles = await viewModel.items.map(\.title)
    XCTAssertTrue(matches.isEmpty)
    XCTAssertEqual(titles, ["newer", "older"])
  }

  func testPinnedRecordsStayFirstDuringFuzzySearch() async throws {
    // A pinned weak (subsequence) match must still be listed before an
    // unpinned strong (substring) match.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "capable item board", lastCopiedAt: 1, isPinned: true, pinnedAt: 1))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "cab", lastCopiedAt: 2))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "cab")

    let items = await viewModel.items
    XCTAssertEqual(items.count, 2)
    XCTAssertTrue(items[0].isPinned)
  }

  func testFuzzyQueryStillMatchesSourceAppName() async throws {
    // The query hits only the source app name, not the content.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "hello world", lastCopiedAt: 1, sourceAppName: "Safari"))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "other", lastCopiedAt: 2, sourceAppName: "Xcode"))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "safari")

    let items = await viewModel.items
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.sourceAppName, "Safari")
  }

  func testDefaultSortOrderIsLastCopiedDescending() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "old", lastCopiedAt: 100))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "new", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "")

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["new", "old"])
  }

  func testCopyCountSortOrderRanksMostCopiedFirst() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "frequent", lastCopiedAt: 100, copyCount: 9))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "recent", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .copyCount)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles.first, "frequent")
  }

  func testFirstCopiedSortOrderUsesCreatedAtDescending() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "created-early", lastCopiedAt: 900, createdAt: 100))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "created-late", lastCopiedAt: 600, createdAt: 500))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .firstCopied)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["created-late", "created-early"])
  }

  func testFirstCopiedSortOrderTieBreaksByLastCopiedAtDescending() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "copied-earlier", lastCopiedAt: 100, createdAt: 500))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "copied-later", lastCopiedAt: 200, createdAt: 500))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .firstCopied)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["copied-later", "copied-earlier"])
  }

  func testSortOrderDoesNotAffectPinnedSectionOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "pinned-low", lastCopiedAt: 100, isPinned: true, pinnedAt: 100, copyCount: 1))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "unpinned-high", lastCopiedAt: 200, copyCount: 50))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .copyCount)

    let items = await viewModel.items
    XCTAssertTrue(items[0].isPinned)
  }

  func testSortOrderIsIgnoredDuringActiveSearch() async throws {
    // Fuzzy score ranking wins while a query is active: the substring hit
    // outranks the scattered subsequence hit despite a huge copyCount.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "cxxlxxixxp", lastCopiedAt: 100, copyCount: 99))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "clip", lastCopiedAt: 50))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "clip", sortOrder: .copyCount)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles.first, "clip")
  }
}
