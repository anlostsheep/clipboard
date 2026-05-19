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

  private func makeRecord(
    id: UUID,
    title: String,
    primaryType: ClipboardContentType = .text,
    lastCopiedAt: TimeInterval,
    groupIds: [String] = [],
    isPinned: Bool = false,
    pinnedAt: TimeInterval? = nil
  ) -> ClipboardRecord {
    ClipboardRecord(
      id: id,
      contentHash: title,
      primaryType: primaryType,
      title: title,
      plainTextPreview: title,
      sourceAppBundleId: nil,
      sourceAppName: "Terminal",
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
      copyCount: 1,
      isPinned: isPinned,
      pinnedAt: pinnedAt.map(Date.init(timeIntervalSince1970:)),
      isFavorite: false,
      groupIds: groupIds,
      retentionExempt: isPinned,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
  }
}
