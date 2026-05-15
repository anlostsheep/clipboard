import XCTest
@testable import ClipboardCore

final class ClipboardIngestServiceTests: XCTestCase {
  func testIngestSkipsIgnoredCapture() async throws {
    let store = InMemoryHistoryStore()
    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.secret.App")
    let service = ClipboardIngestService(store: store, privacyPolicy: policy, largeTextPolicy: .default)

    let capture = ClipboardCapture(
      payload: .text("secret"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.secret.App",
      sourceAppName: "Secret",
      capturedAt: Date(timeIntervalSince1970: 10)
    )

    let record = try await service.ingest(capture)
    let records = try await store.fetchAll()

    XCTAssertNil(record)
    XCTAssertEqual(records.count, 0)
  }

  func testIngestCreatesLargeJsonRecordWithoutFullTitle() async throws {
    let store = InMemoryHistoryStore()
    let service = ClipboardIngestService(store: store, privacyPolicy: .standard, largeTextPolicy: .default)
    let json = "{" + String(repeating: "\"key\":\"value\",", count: 10_000) + "\"end\":true}"

    let capture = ClipboardCapture(
      payload: .text(json),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.apple.Terminal",
      sourceAppName: "Terminal",
      capturedAt: Date(timeIntervalSince1970: 11)
    )

    let ingestedRecord = try await service.ingest(capture)
    let record = try XCTUnwrap(ingestedRecord)
    let records = try await store.fetchAll()

    XCTAssertTrue(record.isLargeContent)
    XCTAssertLessThanOrEqual(record.title.count, 120)
    XCTAssertLessThanOrEqual(record.plainTextPreview?.count ?? 0, 2_048)
    XCTAssertNotEqual(record.plainTextPreview, json)
    XCTAssertEqual(record.metadata?.contentClass, .json)
    XCTAssertEqual(record.metadata?.previewExcerpt, record.plainTextPreview)
    XCTAssertEqual(record.metadata?.tailExcerpt, String(json.suffix(2_048)))
    XCTAssertEqual(record.metadata?.blobStoragePolicy, .full)
    XCTAssertEqual(record.metadata?.indexingState, .excerptIndexed)
    XCTAssertEqual(records.count, 1)
  }

  func testIngestClassifiesHTTPURLTextAsLink() async throws {
    let store = InMemoryHistoryStore()
    let service = ClipboardIngestService(store: store, privacyPolicy: .standard, largeTextPolicy: .default)
    let capture = ClipboardCapture(
      payload: .text("https://example.com/path?q=1"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.apple.Safari",
      sourceAppName: "Safari",
      capturedAt: Date(timeIntervalSince1970: 12)
    )

    let ingestedRecord = try await service.ingest(capture)
    let record = try XCTUnwrap(ingestedRecord)

    XCTAssertEqual(record.primaryType, .link)
    XCTAssertEqual(record.title, "https://example.com/path?q=1")
    XCTAssertEqual(record.plainTextPreview, "https://example.com/path?q=1")
  }

  func testPayloadStoreSavesAndLoadsPayloadByRecordID() async throws {
    let store = InMemoryPayloadStore()
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000060")!

    try await store.save(.text("hello"), for: id)
    let payload = try await store.loadPayload(for: id)

    XCTAssertEqual(payload, .text("hello"))
  }

  func testPayloadStoreReturnsNilForMissingRecordID() async throws {
    let store = InMemoryPayloadStore()
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!

    let payload = try await store.loadPayload(for: id)

    XCTAssertNil(payload)
  }
}
