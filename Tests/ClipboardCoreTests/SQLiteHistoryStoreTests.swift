import XCTest
@testable import ClipboardCore

final class SQLiteHistoryStoreTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func makeStore() throws -> SQLiteHistoryStore {
    try SQLiteHistoryStore(databaseFile: tempDir.appendingPathComponent("test.sqlite"))
  }

  func testColdStartRecoversRecords() async throws {
    let storeA = try makeStore()
    _ = try await storeA.upsert(makeRecord(hash: "a", title: "alpha"))
    _ = try await storeA.upsert(makeRecord(hash: "b", title: "beta"))
    await storeA.close()

    let storeB = try makeStore()
    let titles = try await storeB.fetchAll().map(\.title).sorted()
    XCTAssertEqual(titles, ["alpha", "beta"])
  }

  func testCountReflectsInsertions() async throws {
    let store = try makeStore()
    let initialCount = try await store.count()
    XCTAssertEqual(initialCount, 0)
    _ = try await store.upsert(makeRecord(hash: "a"))
    let countAfter = try await store.count()
    XCTAssertEqual(countAfter, 1)
  }
}

private func makeRecord(hash: String, title: String = "title") -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: .text,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date(timeIntervalSince1970: 0),
    copyCount: 1,
    isPinned: false,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
