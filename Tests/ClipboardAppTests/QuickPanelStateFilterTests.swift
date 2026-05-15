import XCTest
@testable import ClipboardApp
@testable import ClipboardCore

@MainActor
final class QuickPanelStateFilterTests: XCTestCase {
  func testContentTypeFilterRefreshesVisibleItems() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1))
    _ = try await store.upsert(makePanelRecord(hash: "image", title: "Image", type: .image, lastCopiedAt: 2))
    let state = QuickPanelState(
      viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
      payloadStore: InMemoryPayloadStore(),
      pasteController: PasteController(
        pasteboard: AppTestPasteboardWriter(),
        eventPoster: AppTestPasteEventPoster()
      )
    )

    await state.refresh()
    state.updateContentFilter(.image)
    await state.refresh()

    XCTAssertEqual(state.items.map(\.title), ["Image"])
  }
}

private func makePanelRecord(
  hash: String,
  title: String,
  type: ClipboardContentType,
  lastCopiedAt: TimeInterval
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
    isPinned: false,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: []
  )
}

private final class AppTestPasteboardWriter: PasteboardWriting, @unchecked Sendable {
  func write(payload: ClipboardPayload, marker: String) async -> Bool { true }
  func containsMarker(_ marker: String) async -> Bool { true }
}

private final class AppTestPasteEventPoster: PasteEventPosting, @unchecked Sendable {
  func isAccessibilityTrusted() -> Bool { true }
  func postCommandV() async -> Bool { true }
}
