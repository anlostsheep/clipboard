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
      payloadStore: payloadStore,
      failureHandler: NoopFailureHandler()
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

  func testCaptureControlSkipsBeforePayloadSave() async throws {
    let capture = ClipboardCapture(
      payload: .text("secret"),
      pasteboardTypes: ["com.example.secret"],
      sourceAppBundleId: "com.example.Source",
      sourceAppName: "Source App",
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    let reader = FakePasteboardReader(changeCount: 1, capture: capture)
    let store = InMemoryHistoryStore()
    var policy = PrivacyPolicy.standard
    policy.ignoredPasteboardTypes.insert("com.example.secret")
    let payloadStore = CountingPayloadStore()
    let coordinator = ClipboardCaptureCoordinator(
      monitor: ClipboardMonitor(reader: reader),
      ingestService: ClipboardIngestService(
        store: store,
        privacyPolicy: .standard,
        largeTextPolicy: .default
      ),
      payloadStore: payloadStore,
      failureHandler: NoopFailureHandler(),
      captureControl: CaptureControlService(policy: policy)
    )

    let record = try await coordinator.captureLatestChange()
    let storeCount = try await store.count()
    let payloadSaveCount = await payloadStore.currentSaveCount()

    XCTAssertNil(record)
    XCTAssertEqual(storeCount, 0)
    XCTAssertEqual(payloadSaveCount, 0)
  }

  func testCaptureControlAllowBypassesLegacyIngestPrivacyFilter() async throws {
    let capture = ClipboardCapture(
      payload: .text("allowed by live policy"),
      pasteboardTypes: ["com.example.live-allowed"],
      sourceAppBundleId: "com.example.Source",
      sourceAppName: "Source App",
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    let reader = FakePasteboardReader(changeCount: 1, capture: capture)
    let store = InMemoryHistoryStore()
    var legacyPolicy = PrivacyPolicy.standard
    legacyPolicy.ignoredPasteboardTypes.insert("com.example.live-allowed")
    var livePolicy = PrivacyPolicy.standard
    livePolicy.ignoredPasteboardTypes.removeAll()
    let payloadStore = CountingPayloadStore()
    let coordinator = ClipboardCaptureCoordinator(
      monitor: ClipboardMonitor(reader: reader),
      ingestService: ClipboardIngestService(
        store: store,
        privacyPolicy: legacyPolicy,
        largeTextPolicy: .default
      ),
      payloadStore: payloadStore,
      failureHandler: NoopFailureHandler(),
      captureControl: CaptureControlService(policy: livePolicy)
    )

    let record = try await coordinator.captureLatestChange()
    let storeCount = try await store.count()
    let payloadSaveCount = await payloadStore.currentSaveCount()

    XCTAssertEqual(record?.title, "allowed by live policy")
    XCTAssertEqual(storeCount, 1)
    XCTAssertEqual(payloadSaveCount, 1)
  }
}

private struct NoopFailureHandler: StorageFailureHandler {
  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool { true }
  func reportSuccess() async {}
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

private actor CountingPayloadStore: ClipboardPayloadStore {
  private var saveCount = 0

  func currentSaveCount() -> Int {
    saveCount
  }

  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    saveCount += 1
  }

  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    nil
  }

  func delete(for recordID: UUID) async throws {}
}
