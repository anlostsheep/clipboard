import XCTest
@testable import ClipboardCore

final class HistoryMutationServiceTests: XCTestCase {
  func testDeleteRecordRemovesRecordAndPayload() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = HistoryMutationService(store: history, payloadStore: payloads)
    let record = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
      hash: "delete"
    )
    _ = try await history.upsert(record)
    try await payloads.save(.text("payload"), for: record.id)

    try await service.deleteRecord(id: record.id)

    let count = try await history.count()
    let payload = try await payloads.loadPayload(for: record.id)
    XCTAssertEqual(count, 0)
    XCTAssertNil(payload)
  }

  func testDeleteRecordWorksThroughProductionStorageWrappers() async throws {
    let sqliteLikeHistory = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let healing = SelfHealingHistoryStore(underlying: sqliteLikeHistory)
    let cleaning = PayloadCleaningHistoryStore(underlying: healing, payloadStore: payloads)
    let service = HistoryMutationService(store: cleaning, payloadStore: payloads)
    let record = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000406")!,
      hash: "wrapped-delete"
    )
    _ = try await cleaning.upsert(record)
    try await payloads.save(.text("payload"), for: record.id)

    try await service.deleteRecord(id: record.id)

    let remaining = try await cleaning.fetchAll()
    let payload = try await payloads.loadPayload(for: record.id)
    XCTAssertTrue(remaining.isEmpty)
    XCTAssertNil(payload)
  }

  func testTogglePinnedUpdatesRetentionExempt() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let pinnedAt = Date(timeIntervalSince1970: 123)
    let service = HistoryMutationService(store: history, payloadStore: payloads, now: { pinnedAt })
    let record = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
      hash: "pin",
      isPinned: false,
      isFavorite: false,
      retentionExempt: false
    )
    _ = try await history.upsert(record)

    let updated = try await service.togglePinned(id: record.id)

    XCTAssertTrue(updated.isPinned)
    XCTAssertTrue(updated.retentionExempt)
    XCTAssertEqual(updated.pinnedAt, pinnedAt)
    let stored = try await history.fetchAll().first
    XCTAssertEqual(stored?.id, record.id)
    XCTAssertEqual(stored?.isPinned, true)
    XCTAssertEqual(stored?.retentionExempt, true)
    XCTAssertEqual(stored?.pinnedAt, pinnedAt)
  }

  func testTogglePinnedClearsPinnedAtWhenUnpinning() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = HistoryMutationService(store: history, payloadStore: payloads)
    let record = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000407")!,
      hash: "unpin",
      isPinned: true,
      retentionExempt: true,
      pinnedAt: Date(timeIntervalSince1970: 5)
    )
    _ = try await history.upsert(record)

    let updated = try await service.togglePinned(id: record.id)

    XCTAssertFalse(updated.isPinned)
    XCTAssertFalse(updated.retentionExempt)
    XCTAssertNil(updated.pinnedAt)
  }

  func testClearUnpinnedPreservesPinnedRecordsAndRemovesUnpinnedPayloads() async throws {
    let history = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = HistoryMutationService(store: history, payloadStore: payloads)
    let pinned = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
      hash: "pinned",
      isPinned: true
    )
    let first = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000404")!,
      hash: "first"
    )
    let second = makeMutationRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000405")!,
      hash: "second"
    )
    _ = try await history.upsert(pinned)
    _ = try await history.upsert(first)
    _ = try await history.upsert(second)
    try await payloads.save(.text("pinned"), for: pinned.id)
    try await payloads.save(.text("first"), for: first.id)
    try await payloads.save(.text("second"), for: second.id)

    let removed = try await service.clearUnpinned()

    let remaining = try await history.fetchAll()
    let pinnedPayload = try await payloads.loadPayload(for: pinned.id)
    let firstPayload = try await payloads.loadPayload(for: first.id)
    let secondPayload = try await payloads.loadPayload(for: second.id)
    XCTAssertEqual(removed, 2)
    XCTAssertEqual(remaining.map(\.id), [pinned.id])
    XCTAssertEqual(pinnedPayload, .text("pinned"))
    XCTAssertNil(firstPayload)
    XCTAssertNil(secondPayload)
  }
}

private func makeMutationRecord(
  id: UUID,
  hash: String,
  isPinned: Bool = false,
  isFavorite: Bool = false,
  retentionExempt: Bool = false,
  pinnedAt: Date? = nil
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
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date(timeIntervalSince1970: 0),
    copyCount: 1,
    isPinned: isPinned,
    pinnedAt: pinnedAt,
    isFavorite: isFavorite,
    groupIds: [],
    retentionExempt: retentionExempt,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
