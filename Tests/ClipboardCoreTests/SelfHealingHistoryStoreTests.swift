import XCTest
@testable import ClipboardCore

final class SelfHealingHistoryStoreTests: XCTestCase {
  func testSucceedsAfterEvictingOnce() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([.failure(StorageError.full), .success(())])
    await fake.setEvictResult(5)

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)
    let record = makeRecord(hash: "x")
    let result = try await store.upsert(record)

    let evictCount = await fake.evictCallCount
    let upsertCount = await fake.upsertCallCount
    XCTAssertEqual(result.contentHash, "x")
    XCTAssertEqual(evictCount, 1)
    XCTAssertEqual(upsertCount, 2)
  }

  func testThrowsFullAndCannotEvictWhenEvictReturnsZero() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([.failure(StorageError.full)])
    await fake.setEvictResult(0)

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)

    do {
      _ = try await store.upsert(makeRecord(hash: "x"))
      XCTFail("应抛错")
    } catch StorageError.fullAndCannotEvict {
      // OK
    }
    let evictCount = await fake.evictCallCount
    XCTAssertEqual(evictCount, 1)
  }

  func testGivesUpAfterMaxRounds() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([
      .failure(StorageError.full),
      .failure(StorageError.full),
      .failure(StorageError.full),
      .failure(StorageError.full)
    ])
    await fake.setEvictResult(3)

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)
    do {
      _ = try await store.upsert(makeRecord(hash: "x"))
      XCTFail("应抛错")
    } catch StorageError.full {
      // OK: exhausted maxRounds, re-throw .full for Layer 2 to handle
    }
    let evictCount = await fake.evictCallCount
    let upsertCount = await fake.upsertCallCount
    XCTAssertEqual(evictCount, 3)
    XCTAssertEqual(upsertCount, 4)  // initial + 3 retries
  }

  func testForwardsOtherErrorsUntouched() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([.failure(StorageError.underlying("disk read"))])

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)
    do {
      _ = try await store.upsert(makeRecord(hash: "x"))
      XCTFail("应抛错")
    } catch StorageError.underlying {
      // OK
    }
    let evictCount = await fake.evictCallCount
    XCTAssertEqual(evictCount, 0)
  }
}

actor FakeHistoryStore: HistoryStore {
  private var upsertScript: [Result<Void, Error>] = []
  private var evictReturn: Int = 0
  private(set) var upsertCallCount = 0
  private(set) var evictCallCount = 0
  private var stored: [String: ClipboardRecord] = [:]

  func scheduleUpsertResults(_ results: [Result<Void, Error>]) { upsertScript = results }
  func setEvictResult(_ n: Int) { evictReturn = n }

  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    upsertCallCount += 1
    if !upsertScript.isEmpty {
      let next = upsertScript.removeFirst()
      if case .failure(let err) = next { throw err }
    }
    stored[record.contentHash] = record
    return record
  }

  func fetchAll() async throws -> [ClipboardRecord] { Array(stored.values) }
  func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord] {
    Array(stored.values.filter { query.matches($0) }.prefix(limit))
  }
  func count() async throws -> Int { stored.count }
  func removeAll() async throws { stored.removeAll() }
  func evictOldest(percent: Double) async throws -> Int {
    evictCallCount += 1
    return evictReturn
  }
}

private func makeRecord(hash: String) -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: .text,
    title: hash,
    plainTextPreview: hash,
    sourceAppBundleId: nil,
    sourceAppName: nil,
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date(timeIntervalSince1970: 0),
    copyCount: 1,
    isPinned: false,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: []
  )
}
