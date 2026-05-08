import XCTest
@testable import ClipboardCore

final class ClipboardCaptureCoordinatorTests: XCTestCase {
  func testCaptureLatestChangeStoresRecordBeforeQuickPanelRefresh() async throws {
    let capture = ClipboardCapture(
      payload: .text("instant quick panel item"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.example.Source",
      sourceAppName: "Source App",
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    let reader = FakePasteboardReader(changeCount: 1, capture: capture)
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let coordinator = ClipboardCaptureCoordinator(
      monitor: ClipboardMonitor(reader: reader),
      ingestService: ClipboardIngestService(
        store: store,
        privacyPolicy: .standard,
        largeTextPolicy: .default
      ),
      payloadStore: payloadStore
    )

    let record = try await coordinator.captureLatestChange()

    XCTAssertEqual(record?.title, "instant quick panel item")

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 10)
    await viewModel.refresh(query: "")
    let items = await viewModel.items

    XCTAssertEqual(items.map(\.title), ["instant quick panel item"])
    let firstItem = try XCTUnwrap(items.first)
    let payload = try await payloadStore.loadPayload(for: firstItem.id)
    XCTAssertEqual(payload, .text("instant quick panel item"))
  }
}

private final class FakePasteboardReader: PasteboardReading {
  let changeCount: Int
  let capture: ClipboardCapture?

  init(changeCount: Int, capture: ClipboardCapture?) {
    self.changeCount = changeCount
    self.capture = capture
  }

  func currentChangeCount() async -> Int {
    changeCount
  }

  func readCurrentCapture() async -> ClipboardCapture? {
    capture
  }
}
