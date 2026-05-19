import XCTest
@testable import ClipboardCore

/// Generic contract tests. SQLiteHistoryStore will later have its own XCTestCase subclass
/// that calls runHistoryStoreConformance(_:).
final class InMemoryHistoryStoreConformanceTests: XCTestCase {
  func testInMemoryConformsToContract() async throws {
    try await runHistoryStoreConformance { InMemoryHistoryStore() }
  }

  func testInMemoryConformsToMutationContract() async throws {
    try await runHistoryMutationStoreConformance { InMemoryHistoryStore() }
  }
}

func runHistoryStoreConformance<S: HistoryStore>(
  _ makeStore: () async throws -> S,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  try await assertUpsertDeduplicatesByHash(makeStore, file: file, line: line)
  try await assertFetchPageReturnsByRecency(makeStore, file: file, line: line)
  try await assertFetchPageFiltersByQuery(makeStore, file: file, line: line)
  try await assertFetchPageFiltersByContentType(makeStore, file: file, line: line)
  try await assertFetchPageFiltersByGroup(makeStore, file: file, line: line)
  try await assertCountReflectsRecords(makeStore, file: file, line: line)
  try await assertRemoveAllClearsStore(makeStore, file: file, line: line)
  try await assertEvictOldestRespectsExemptions(makeStore, file: file, line: line)
  try await assertEvictOldestRoundsUp(makeStore, file: file, line: line)
}

func runHistoryMutationStoreConformance<S: HistoryMutationStore>(
  _ makeStore: () async throws -> S,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  try await assertDeleteRecordByIDUpdatesCount(makeStore, file: file, line: line)
  try await assertReplaceMissingRecordThrows(makeStore, file: file, line: line)
}

private func makeRecord(
  id: UUID = UUID(),
  hash: String,
  title: String = "title",
  primaryType: ClipboardContentType = .text,
  lastCopiedAt: TimeInterval = 0,
  isPinned: Bool = false,
  isFavorite: Bool = false,
  retentionExempt: Bool = false,
  groupIds: [String] = []
) -> ClipboardRecord {
  ClipboardRecord(
    id: id,
    contentHash: hash,
    primaryType: primaryType,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: lastCopiedAt),
    lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: isFavorite,
    groupIds: groupIds,
    retentionExempt: retentionExempt,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}

private func assertUpsertDeduplicatesByHash<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "h", lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "h", lastCopiedAt: 2))
  let total = try await store.count()
  XCTAssertEqual(total, 1, "Same content_hash 应去重", file: file, line: line)
}

private func assertFetchPageReturnsByRecency<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "older", lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "b", title: "newer", lastCopiedAt: 2))
  let page = try await store.fetchPage(query: "", limit: 10)
  XCTAssertEqual(page.map(\.title), ["newer", "older"], file: file, line: line)
}

private func assertFetchPageFiltersByQuery<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "alpha", lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "b", title: "beta", lastCopiedAt: 2))
  let page = try await store.fetchPage(query: "alp", limit: 10)
  XCTAssertEqual(page.map(\.title), ["alpha"], file: file, line: line)
}

private func assertFetchPageFiltersByContentType<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "docs", primaryType: .text, lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "b", title: "site", primaryType: .link, lastCopiedAt: 2))
  let page = try await store.fetchPage(
    HistoryQuery(text: "", contentTypes: [.link], groupIDs: []),
    limit: 10
  )
  XCTAssertEqual(page.map(\.title), ["site"], file: file, line: line)
}

private func assertFetchPageFiltersByGroup<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "personal", lastCopiedAt: 1, groupIds: ["home"]))
  _ = try await store.upsert(makeRecord(hash: "b", title: "ticket", lastCopiedAt: 2, groupIds: ["work", "today"]))
  let page = try await store.fetchPage(
    HistoryQuery(text: "", contentTypes: [], groupIDs: ["work"]),
    limit: 10
  )
  XCTAssertEqual(page.map(\.title), ["ticket"], file: file, line: line)
}

private func assertCountReflectsRecords<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  let initial = try await store.count()
  XCTAssertEqual(initial, 0, file: file, line: line)
  _ = try await store.upsert(makeRecord(hash: "a"))
  _ = try await store.upsert(makeRecord(hash: "b"))
  let finalCount = try await store.count()
  XCTAssertEqual(finalCount, 2, file: file, line: line)
}

private func assertRemoveAllClearsStore<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a"))
  try await store.removeAll()
  let countAfterRemove = try await store.count()
  XCTAssertEqual(countAfterRemove, 0, file: file, line: line)
}

private func assertEvictOldestRespectsExemptions<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "old-pinned", lastCopiedAt: 1, isPinned: true))
  _ = try await store.upsert(makeRecord(hash: "b", title: "old-fav", lastCopiedAt: 2, isFavorite: true))
  _ = try await store.upsert(makeRecord(hash: "c", title: "old-exempt", lastCopiedAt: 3, retentionExempt: true))
  _ = try await store.upsert(makeRecord(hash: "d", title: "candidate-old", lastCopiedAt: 4))
  _ = try await store.upsert(makeRecord(hash: "e", title: "candidate-new", lastCopiedAt: 5))

  let removed = try await store.evictOldest(percent: 0.5)  // ceil(2 * 0.5) = 1
  XCTAssertEqual(removed, 1, file: file, line: line)

  let remaining = try await store.fetchAll().map(\.title).sorted()
  XCTAssertEqual(remaining, ["candidate-new", "old-exempt", "old-fav", "old-pinned"], file: file, line: line)
}

private func assertEvictOldestRoundsUp<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", lastCopiedAt: 1))
  // 1 candidate × 0.10 = 0.1 → ceil = 1, should delete the only record
  let removed = try await store.evictOldest(percent: 0.10)
  XCTAssertEqual(removed, 1, file: file, line: line)
  let countAfterEvict = try await store.count()
  XCTAssertEqual(countAfterEvict, 0, file: file, line: line)
}

private func assertDeleteRecordByIDUpdatesCount<S: HistoryMutationStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
  let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
  _ = try await store.upsert(makeRecord(id: firstID, hash: "a"))
  _ = try await store.upsert(makeRecord(id: secondID, hash: "b"))

  let removed = try await store.deleteRecord(id: firstID)
  let countAfterDelete = try await store.count()
  let remainingIDs = try await store.fetchAll().map(\.id)

  XCTAssertEqual(removed?.id, firstID, file: file, line: line)
  XCTAssertEqual(countAfterDelete, 1, file: file, line: line)
  XCTAssertEqual(remainingIDs, [secondID], file: file, line: line)
}

private func assertReplaceMissingRecordThrows<S: HistoryMutationStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  let missing = makeRecord(
    id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
    hash: "missing"
  )

  do {
    _ = try await store.replaceRecord(missing)
    XCTFail("Expected missing replace to throw", file: file, line: line)
  } catch HistoryMutationError.recordNotFound {
    let count = try await store.count()
    XCTAssertEqual(count, 0, file: file, line: line)
  }
}

// MARK: - SQLiteHistoryStore conformance

final class SQLiteHistoryStoreConformanceTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-conformance-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testSQLiteConformsToContract() async throws {
    let counter = TestCounter()
    let dir = tempDir!  // capture for closure; avoids implicitly-unwrapped optional in async context
    // Use a permissive RetentionPolicy so that records with epoch-era timestamps
    // (used by the conformance helpers) are never evicted during assertions.
    let policy = RetentionPolicy(maxCount: 100_000, maxAgeDays: 365 * 200)
    try await runHistoryStoreConformance {
      let n = await counter.next()
      let url = dir.appendingPathComponent("test-\(n).sqlite")
      return try SQLiteHistoryStore(databaseFile: url, retentionPolicy: policy)
    }
  }

  func testSQLiteConformsToMutationContract() async throws {
    let counter = TestCounter()
    let dir = tempDir!
    let policy = RetentionPolicy(maxCount: 100_000, maxAgeDays: 365 * 200)
    try await runHistoryMutationStoreConformance {
      let n = await counter.next()
      let url = dir.appendingPathComponent("mutation-\(n).sqlite")
      return try SQLiteHistoryStore(databaseFile: url, retentionPolicy: policy)
    }
  }
}

/// Provides an isolated, monotonically increasing counter for unique DB filenames
/// across parallel assertion helpers.
actor TestCounter {
  private var n = 0
  func next() -> Int {
    n += 1
    return n
  }
}
