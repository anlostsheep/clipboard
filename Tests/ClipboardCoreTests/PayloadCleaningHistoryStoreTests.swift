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
}

private func makeCleaningRecord(id: UUID, hash: String, lastCopiedAt: TimeInterval) -> ClipboardRecord {
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
    isPinned: false,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
