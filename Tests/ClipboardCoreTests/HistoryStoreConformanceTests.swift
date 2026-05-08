import XCTest
@testable import ClipboardCore

/// Generic contract tests. SQLiteHistoryStore will later have its own XCTestCase subclass
/// that calls runHistoryStoreConformance(_:).
final class InMemoryHistoryStoreConformanceTests: XCTestCase {
  func testInMemoryConformsToContract() async throws {
    try await runHistoryStoreConformance { InMemoryHistoryStore() }
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
  try await assertCountReflectsRecords(makeStore, file: file, line: line)
  try await assertRemoveAllClearsStore(makeStore, file: file, line: line)
  try await assertEvictOldestRespectsExemptions(makeStore, file: file, line: line)
  try await assertEvictOldestRoundsUp(makeStore, file: file, line: line)
}

private func makeRecord(
  id: UUID = UUID(),
  hash: String,
  title: String = "title",
  lastCopiedAt: TimeInterval = 0,
  isPinned: Bool = false,
  isFavorite: Bool = false,
  retentionExempt: Bool = false
) -> ClipboardRecord {
  ClipboardRecord(
    id: id,
    contentHash: hash,
    primaryType: .text,
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
    groupIds: [],
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
