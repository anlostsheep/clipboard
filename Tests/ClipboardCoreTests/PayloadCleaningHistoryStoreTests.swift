import XCTest
@testable import ClipboardCore

final class PayloadCleaningHistoryStoreTests: XCTestCase {
  func testRemoveAllDeletesPayloadsForRemovedRecords() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let first = makeCleaningRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!, hash: "a", lastCopiedAt: 1)
    let second = makeCleaningRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!, hash: "b", lastCopiedAt: 2)
    _ = try await store.upsert(first)
    _ = try await store.upsert(second)
    try await payloads.save(.text("a"), for: first.id)
    try await payloads.save(.text("b"), for: second.id)

    try await store.removeAll()

    let firstPayload = try await payloads.loadPayload(for: first.id)
    let secondPayload = try await payloads.loadPayload(for: second.id)
    XCTAssertNil(firstPayload)
    XCTAssertNil(secondPayload)
  }

  func testEvictOldestDeletesOnlyPayloadsForEvictedRecords() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let old = makeCleaningRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!, hash: "old", lastCopiedAt: 1)
    let new = makeCleaningRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000204")!, hash: "new", lastCopiedAt: 2)
    _ = try await store.upsert(old)
    _ = try await store.upsert(new)
    try await payloads.save(.text("old"), for: old.id)
    try await payloads.save(.text("new"), for: new.id)

    let removed = try await store.evictOldest(percent: 0.5)

    let oldPayload = try await payloads.loadPayload(for: old.id)
    let newPayload = try await payloads.loadPayload(for: new.id)
    XCTAssertEqual(removed, 1)
    XCTAssertNil(oldPayload)
    XCTAssertEqual(newPayload, .text("new"))
  }

  func testClearUnpinnedDeletesOnlyPayloadsForRemovedRecords() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let pinned = makeCleaningRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000205")!,
      hash: "pinned",
      lastCopiedAt: 1,
      isPinned: true
    )
    let unpinned = makeCleaningRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000206")!,
      hash: "unpinned",
      lastCopiedAt: 2
    )
    _ = try await store.upsert(pinned)
    _ = try await store.upsert(unpinned)
    try await payloads.save(.text("pinned"), for: pinned.id)
    try await payloads.save(.text("unpinned"), for: unpinned.id)

    let removed = try await store.clearUnpinned()

    let pinnedPayload = try await payloads.loadPayload(for: pinned.id)
    let unpinnedPayload = try await payloads.loadPayload(for: unpinned.id)
    XCTAssertEqual(removed.map(\.id), [unpinned.id])
    XCTAssertEqual(pinnedPayload, .text("pinned"))
    XCTAssertNil(unpinnedPayload)
  }

  func testDeleteRecordDeletesPayloadForRemovedRecord() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let record = makeCleaningRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000207")!,
      hash: "deleted",
      lastCopiedAt: 3
    )
    _ = try await store.upsert(record)
    try await payloads.save(.text("deleted"), for: record.id)

    let removed = try await store.deleteRecord(id: record.id)

    let payload = try await payloads.loadPayload(for: record.id)
    XCTAssertEqual(removed?.id, record.id)
    XCTAssertNil(payload)
  }

  func testDeleteRecordSurfacesPayloadDeletionFailure() async throws {
    let history = InMemoryHistoryStore()
    let payloads = FailingDeletePayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let record = makeCleaningRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000208")!,
      hash: "payload-delete-failure",
      lastCopiedAt: 4
    )
    _ = try await store.upsert(record)

    do {
      _ = try await store.deleteRecord(id: record.id)
      XCTFail("Expected payload deletion failure")
    } catch TestPayloadError.deleteFailed {
      let count = try await history.count()
      XCTAssertEqual(count, 0)
    }
  }

  func testClearUnpinnedSurfacesPayloadDeletionFailure() async throws {
    let history = InMemoryHistoryStore()
    let payloads = FailingDeletePayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let record = makeCleaningRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000209")!,
      hash: "payload-clear-failure",
      lastCopiedAt: 5
    )
    _ = try await store.upsert(record)

    do {
      _ = try await store.clearUnpinned()
      XCTFail("Expected payload deletion failure")
    } catch TestPayloadError.deleteFailed {
      let count = try await history.count()
      XCTAssertEqual(count, 0)
    }
  }

  func testMutationFallbacksWhenUnderlyingStoreDoesNotSupportMutation() async throws {
    let history = NonMutatingHistoryStore()
    let payloads = InMemoryPayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: history, payloadStore: payloads)
    let record = makeCleaningRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000210")!,
      hash: "fallback",
      lastCopiedAt: 6
    )

    let deleted = try await store.deleteRecord(id: record.id)
    let cleared = try await store.clearUnpinned()
    let replaced = try await store.replaceRecord(record)
    let count = try await history.count()

    XCTAssertNil(deleted)
    XCTAssertEqual(cleared, [])
    XCTAssertEqual(replaced.id, record.id)
    XCTAssertEqual(count, 1)
  }

  func testWrappedStoreChainSupportsImportWritableHistoryStore() async throws {
    let history = InMemoryHistoryStore()
    let healing = SelfHealingHistoryStore(underlying: history)
    let payloads = InMemoryPayloadStore()
    let store = PayloadCleaningHistoryStore(underlying: healing, payloadStore: payloads)
    let importing = store as any ImportWritableHistoryStore
    let record = makeCleaningRecord(id: UUID(), hash: "imported", lastCopiedAt: 3)

    let imported = try await importing.importRecord(record)
    let found = try await importing.record(forContentHash: "imported")

    XCTAssertEqual(imported.id, record.id)
    XCTAssertEqual(found?.id, record.id)
    XCTAssertEqual(found?.contentHash, "imported")
  }
}

private func makeCleaningRecord(
  id: UUID,
  hash: String,
  lastCopiedAt: TimeInterval,
  isPinned: Bool = false
) -> ClipboardRecord {
  ClipboardRecord(
    id: id,
    contentHash: hash,
    primaryType: .text,
    title: hash,
    plainTextPreview: hash,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: lastCopiedAt),
    lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}

private enum TestPayloadError: Error {
  case deleteFailed
}

private actor FailingDeletePayloadStore: ClipboardPayloadStore {
  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {}
  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? { nil }
  func delete(for recordID: UUID) async throws {
    throw TestPayloadError.deleteFailed
  }
}

private actor NonMutatingHistoryStore: HistoryStore {
  private var recordsByHash: [String: ClipboardRecord] = [:]

  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    recordsByHash[record.contentHash] = record
    return record
  }

  func fetchAll() async throws -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord] {
    Array(recordsByHash.values.filter { query.matches($0) }.prefix(limit))
  }

  func count() async throws -> Int {
    recordsByHash.count
  }

  func removeAll() async throws {
    recordsByHash.removeAll()
  }

  func evictOldest(percent: Double) async throws -> Int {
    0
  }
}
