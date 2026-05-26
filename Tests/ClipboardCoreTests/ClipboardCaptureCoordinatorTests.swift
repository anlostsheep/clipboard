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

  func testRichTextCaptureWithSamePlainTextAsPlainTextCreatesDistinctPayloadRecord() async throws {
    let textCapture = ClipboardCapture(
      payload: .text("same visible text"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.example.Source",
      sourceAppName: "Source App",
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    let html = Data("<p><strong>same visible text</strong></p>".utf8)
    let richPayload = ClipboardPayload.richText(plainText: "same visible text", rtfData: nil, htmlData: html)
    let richCapture = ClipboardCapture(
      payload: richPayload,
      pasteboardTypes: ["public.utf8-plain-text", "public.html"],
      sourceAppBundleId: "com.example.Source",
      sourceAppName: "Source App",
      capturedAt: Date(timeIntervalSince1970: 2)
    )
    let reader = SequencePasteboardReader(captures: [textCapture, richCapture])
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

    let first = try await coordinator.captureLatestChange()
    let second = try await coordinator.captureLatestChange()
    let records = try await store.fetchAll()
    let richRecord = try XCTUnwrap(records.first { $0.primaryType == .richText })
    let storedRichPayload = try await payloadStore.loadPayload(for: richRecord.id)

    XCTAssertEqual(first?.primaryType, .text)
    XCTAssertEqual(second?.primaryType, .richText)
    XCTAssertEqual(records.count, 2)
    XCTAssertEqual(storedRichPayload, richPayload)
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

private final class SequencePasteboardReader: PasteboardReading, @unchecked Sendable {
  private var captures: [ClipboardCapture]
  private var index = 0

  init(captures: [ClipboardCapture]) {
    self.captures = captures
  }

  func currentChangeCount() async -> Int {
    index + 1
  }

  func readCurrentCapture() async -> ClipboardCapture? {
    guard captures.indices.contains(index) else {
      return nil
    }
    defer { index += 1 }
    return captures[index]
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
