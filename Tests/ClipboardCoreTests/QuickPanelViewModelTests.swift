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

  private func makeRecord(id: UUID, title: String, lastCopiedAt: TimeInterval) -> ClipboardRecord {
    ClipboardRecord(
      id: id,
      contentHash: title,
      primaryType: .text,
      title: title,
      plainTextPreview: title,
      sourceAppBundleId: nil,
      sourceAppName: "Terminal",
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
  }
}
