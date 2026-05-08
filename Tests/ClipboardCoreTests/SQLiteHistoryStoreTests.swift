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

  func testEnforceRetentionTrimsByCount() async throws {
    let store = try SQLiteHistoryStore(
      databaseFile: tempDir.appendingPathComponent("test.sqlite"),
      retentionPolicy: RetentionPolicy(maxCount: 3, maxAgeDays: 365)
    )
    for i in 1...5 {
      _ = try await store.upsert(makeRecord(hash: "h\(i)", title: "t\(i)"))
    }
    // dual-gate should trim the oldest 2 records after the last upsert
    let count = try await store.count()
    XCTAssertEqual(count, 3)
  }

  func testEnforceRetentionExemptsPinnedAndFavorite() async throws {
    let store = try SQLiteHistoryStore(
      databaseFile: tempDir.appendingPathComponent("test.sqlite"),
      retentionPolicy: RetentionPolicy(maxCount: 1, maxAgeDays: 365)
    )
    _ = try await store.upsert(makeRecord(hash: "pin", title: "p", isPinned: true))
    _ = try await store.upsert(makeRecord(hash: "fav", title: "f", isFavorite: true))
    _ = try await store.upsert(makeRecord(hash: "normal", title: "n"))
    // maxCount = 1 but exempt items don't count toward quota: all 3 are kept
    let count = try await store.count()
    XCTAssertEqual(count, 3)
  }

  func testEvictOldestReturnsCount() async throws {
    let store = try SQLiteHistoryStore(databaseFile: tempDir.appendingPathComponent("test.sqlite"))
    for i in 1...10 {
      _ = try await store.upsert(makeRecord(hash: "h\(i)", title: "t\(i)"))
    }
    let removed = try await store.evictOldest(percent: 0.20)
    XCTAssertEqual(removed, 2)  // ceil(10 * 0.2) = 2
    let count = try await store.count()
    XCTAssertEqual(count, 8)
  }

  func testCorruptedDatabaseIsBackedUp() async throws {
    let dbPath = tempDir.appendingPathComponent("test.sqlite")
    // Write garbage content so integrity check fails
    try Data("not a sqlite file".utf8).write(to: dbPath)

    do {
      _ = try SQLiteHistoryStore(databaseFile: dbPath)
      XCTFail("Should have thrown an error or succeeded after auto-backup")
    } catch StorageError.underlying(let msg) {
      XCTAssert(
        msg.contains("integrity") || msg.contains("rc="),
        "Expected integrity or rc= in error message, got: \(msg)"
      )
    }

    // Verify backup file was created
    let entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
    XCTAssert(
      entries.contains(where: { $0.hasPrefix("clipboard.corrupt.") }),
      "Expected backup file with prefix 'clipboard.corrupt.' but found: \(entries)"
    )
  }
}

private func makeRecord(
  hash: String,
  title: String = "title",
  isPinned: Bool = false,
  isFavorite: Bool = false
) -> ClipboardRecord {
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
    lastCopiedAt: Date(timeIntervalSinceNow: -TimeInterval(abs(hash.hashValue) % 10000)),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: isFavorite,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
