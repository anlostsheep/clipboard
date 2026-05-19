import XCTest
import SQLite3
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

  func testImportRecordReplacesFullRecordWithoutIncrementingCopyCount() async throws {
    let store = try makeStore()
    let original = makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
      hash: "same",
      title: "original",
      copyCount: 7,
      lastCopiedAt: 10
    )
    let replacement = makeRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
      hash: "same",
      title: "replacement",
      copyCount: 2,
      lastCopiedAt: 20
    )

    _ = try await store.importRecord(original)
    let imported = try await store.importRecord(replacement)

    XCTAssertEqual(imported.id, replacement.id)
    XCTAssertEqual(imported.title, "replacement")
    XCTAssertEqual(imported.copyCount, 2)
    XCTAssertEqual(imported.lastCopiedAt, replacement.lastCopiedAt)

    await store.close()
    let reopened = try makeStore()
    let records = try await reopened.fetchAll()
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records.first?.id, replacement.id)
    XCTAssertEqual(records.first?.copyCount, 2)
    XCTAssertEqual(records.first?.title, "replacement")
  }

  func testPinnedAtSurvivesColdStart() async throws {
    let storeA = try makeStore()
    let pinnedAt = Date(timeIntervalSince1970: 123)
    _ = try await storeA.importRecord(makeRecord(hash: "pin", title: "p", isPinned: true, pinnedAt: pinnedAt))
    await storeA.close()

    let storeB = try makeStore()
    let records = try await storeB.fetchAll()

    XCTAssertEqual(records.first?.pinnedAt, pinnedAt)
  }

  func testMigratesV1DatabaseByAddingPinnedAtColumn() async throws {
    let dbPath = tempDir.appendingPathComponent("legacy.sqlite")
    do {
      let connection = try SQLiteConnection(path: dbPath.path)
      try connection.exec("""
        CREATE TABLE records (
            id              TEXT PRIMARY KEY,
            content_hash    TEXT NOT NULL UNIQUE,
            primary_type    TEXT NOT NULL,
            title           TEXT NOT NULL,
            plain_preview   TEXT,
            source_bundle   TEXT,
            source_app      TEXT,
            source_device   TEXT NOT NULL,
            created_at      REAL NOT NULL,
            last_copied_at  REAL NOT NULL,
            copy_count      INTEGER NOT NULL,
            is_pinned       INTEGER NOT NULL,
            is_favorite     INTEGER NOT NULL,
            group_ids_json  TEXT NOT NULL,
            retention_exempt INTEGER NOT NULL,
            metadata_json   TEXT,
            pasteboard_types_json TEXT NOT NULL,
            payload_ref     TEXT
        )
      """)
      try connection.exec("CREATE INDEX idx_last_copied_at ON records(last_copied_at DESC)")
      try connection.exec("CREATE INDEX idx_pinned_favorite ON records(is_pinned, is_favorite)")
      try connection.exec("""
        INSERT INTO records (
          id, content_hash, primary_type, title, plain_preview,
          source_bundle, source_app, source_device,
          created_at, last_copied_at, copy_count,
          is_pinned, is_favorite, group_ids_json, retention_exempt,
          metadata_json, pasteboard_types_json, payload_ref
        ) VALUES (
          '00000000-0000-0000-0000-000000000333', 'legacy-pin', 'text', 'legacy pin', 'legacy pin',
          NULL, 'App', 'local',
          1, 2, 1,
          1, 0, '[]', 1,
          NULL, '["public.utf8-plain-text"]', NULL
        )
      """)
      try connection.exec("PRAGMA user_version = 1")
    }

    let store = try SQLiteHistoryStore(databaseFile: dbPath)
    let records = try await store.fetchAll()
    await store.close()

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records.first?.title, "legacy pin")
    XCTAssertEqual(records.first?.isPinned, true)
    XCTAssertNil(records.first?.pinnedAt)

    let connection = try SQLiteConnection(path: dbPath.path)
    XCTAssertEqual(try connection.intScalar("PRAGMA user_version"), SQLiteSchema.currentVersion)
    let stmt = try connection.prepare("PRAGMA table_info(records)")
    defer { stmt.finalize() }
    var columns: [String] = []
    while try stmt.step() == SQLITE_ROW {
      if let name = stmt.columnText(1) {
        columns.append(name)
      }
    }
    XCTAssertTrue(columns.contains("pinned_at"))
  }

  func testRecordForContentHashLooksUpImportedRecord() async throws {
    let store = try makeStore()
    let record = makeRecord(hash: "lookup", title: "lookup title")

    _ = try await store.importRecord(record)

    let found = try await store.record(forContentHash: "lookup")
    let missing = try await store.record(forContentHash: "missing")
    XCTAssertEqual(found?.id, record.id)
    XCTAssertEqual(found?.title, "lookup title")
    XCTAssertNil(missing)
  }

  func testDuplicateUpsertStillIncrementsCopyCount() async throws {
    let store = try makeStore()
    let first = makeRecord(hash: "duplicate", copyCount: 1, lastCopiedAt: 10)
    let second = makeRecord(hash: "duplicate", copyCount: 1, lastCopiedAt: 20)

    _ = try await store.upsert(first)
    let updated = try await store.upsert(second)

    XCTAssertEqual(updated.copyCount, 2)
    XCTAssertEqual(updated.lastCopiedAt, second.lastCopiedAt)
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

  func testUpdateRetentionPolicyAppliesToRunningStore() async throws {
    let store = try SQLiteHistoryStore(
      databaseFile: tempDir.appendingPathComponent("test.sqlite"),
      retentionPolicy: RetentionPolicy(maxCount: 10, maxAgeDays: 365)
    )
    for i in 1...5 {
      _ = try await store.upsert(makeRecord(hash: "h\(i)", title: "t\(i)"))
    }

    try await store.updateRetentionPolicy(RetentionPolicy(maxCount: 2, maxAgeDays: 365))

    let count = try await store.count()
    XCTAssertEqual(count, 2)
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
  id: UUID = UUID(),
  hash: String,
  title: String = "title",
  copyCount: Int = 1,
  lastCopiedAt: TimeInterval? = nil,
  isPinned: Bool = false,
  isFavorite: Bool = false,
  pinnedAt: Date? = nil
) -> ClipboardRecord {
  let copiedAt = Date(timeIntervalSinceNow: -(lastCopiedAt ?? TimeInterval(abs(hash.hashValue) % 10000)))
  return ClipboardRecord(
    id: id,
    contentHash: hash,
    primaryType: .text,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: copiedAt,
    copyCount: copyCount,
    isPinned: isPinned,
    pinnedAt: pinnedAt,
    isFavorite: isFavorite,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
