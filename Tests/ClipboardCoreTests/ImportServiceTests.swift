import XCTest
@testable import ClipboardCore

final class ImportServiceTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-import-service-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testNewRecordsAreInsertedAndPayloadSaved() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    let report = try await service.importRecords([
      .fixture(text: "one", lastCopiedAt: 1),
      .fixture(text: "two", lastCopiedAt: 2, sourceRecordID: "two-id")
    ])

    XCTAssertEqual(report.status, .completed)
    XCTAssertEqual(report.imported, 2)
    XCTAssertEqual(report.lastProcessedSourceRecordID, "two-id")
    let records = try await store.fetchAll()
    XCTAssertEqual(records.count, 2)
    var savedPayloads: [ClipboardPayload] = []
    for record in records {
      if let payload = try await payloads.loadPayload(for: record.id) {
        savedPayloads.append(payload)
      }
    }
    XCTAssertTrue(savedPayloads.contains(.text("one")))
    XCTAssertTrue(savedPayloads.contains(.text("two")))
  }

  func testImportedRecordEvictedByRetentionIsSkippedAndPayloadCleaned() async throws {
    let databaseURL = tempDir.appendingPathComponent("retention.sqlite")
    let payloadDirectory = tempDir.appendingPathComponent("payloads", isDirectory: true)
    let sqlite = try SQLiteHistoryStore(
      databaseFile: databaseURL,
      retentionPolicy: RetentionPolicy(maxCount: 5000, maxAgeDays: 1)
    )
    let payloads = try SQLitePayloadStore(payloadsDirectory: payloadDirectory)
    let store = PayloadCleaningHistoryStore(underlying: sqlite, payloadStore: payloads)
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let overAgeTimestamp = Date().addingTimeInterval(-2 * 86_400).timeIntervalSince1970

    let report = try await service.importRecords([
      .fixture(text: "too old", lastCopiedAt: overAgeTimestamp, sourceRecordID: "retention-skip")
    ], batchSize: 1)

    XCTAssertEqual(report.status, .completed)
    XCTAssertEqual(report.imported, 0)
    XCTAssertEqual(report.skipped, 1)
    XCTAssertTrue(report.warnings.contains { $0.contains("retention policy immediately evicted") })
    let retainedCount = try await store.count()
    let payloadFiles = try await payloads.listAllFilenames()
    XCTAssertEqual(retainedCount, 0)
    XCTAssertEqual(payloadFiles, [])
  }

  func testPayloadSaveFailureThrowsLeavesHistoryEmptyAndWritesFailedReport() async throws {
    let store = InMemoryHistoryStore()
    let payloads = FailingPayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    do {
      _ = try await service.importRecords([.fixture(text: "fails", lastCopiedAt: 1)], batchSize: 1)
      XCTFail("Expected payload save failure to throw")
    } catch {
      let count = try await store.count()
      XCTAssertEqual(count, 0)
      let written = try await readOnlyReport()
      XCTAssertEqual(written.status, .failed)
      XCTAssertEqual(written.failed, 1)
      XCTAssertEqual(written.committedBatchCount, 0)
      XCTAssertEqual(written.failures.count, 1)
      XCTAssertEqual(written.failures.first?.sourceRecordID, "fails")
      XCTAssertEqual(written.failures.first?.source, .clipasteCloud)
      XCTAssertTrue(written.failures.first?.reason.contains("payload unavailable") ?? false)
    }
  }

  func testNewRecordHistoryFailureAfterPayloadSaveDeletesPayloadAndWritesFailedReport() async throws {
    let store = FailingImportHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    do {
      _ = try await service.importRecords([
        .fixture(text: "history-fails", lastCopiedAt: 1, sourceRecordID: "new-history-fails")
      ], batchSize: 1)
      XCTFail("Expected history import failure to throw")
    } catch {
      let attemptedIDs = await store.attemptedImportRecordIDs()
      XCTAssertEqual(attemptedIDs.count, 1)
      if let attemptedID = attemptedIDs.first {
        let payload = try await payloads.loadPayload(for: attemptedID)
        XCTAssertNil(payload)
      }
      let count = try await store.count()
      XCTAssertEqual(count, 0)
      let written = try await readOnlyReport()
      XCTAssertEqual(written.status, .failed)
      XCTAssertEqual(written.failed, 1)
      XCTAssertEqual(written.failures.count, 1)
      XCTAssertEqual(written.failures.first?.sourceRecordID, "new-history-fails")
      XCTAssertTrue(written.failures.first?.reason.contains("history import unavailable") ?? false)
    }
  }

  func testNewRecordHistoryFailureReportsDeleteRollbackFailureWhenPayloadDeleteFails() async throws {
    let store = FailingImportHistoryStore()
    let payloads = FailingDeletePayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    do {
      _ = try await service.importRecords([
        .fixture(text: "delete-fails", lastCopiedAt: 1, sourceRecordID: "new-delete-fails")
      ], batchSize: 1)
      XCTFail("Expected history import failure to throw")
    } catch {
      let written = try await readOnlyReport()
      XCTAssertEqual(written.status, .failed)
      XCTAssertEqual(written.failed, 1)
      XCTAssertEqual(written.failures.first?.sourceRecordID, "new-delete-fails")
      let reason = written.failures.first?.reason ?? ""
      XCTAssertTrue(reason.contains("history import unavailable"))
      XCTAssertTrue(reason.contains("payload delete unavailable"))
    }
  }

  func testReplacementPayloadSaveFailureLeavesExistingRecordUnchangedAndWritesFailedReport() async throws {
    let store = InMemoryHistoryStore()
    let payloads = FailingPayloadStore()
    let builder = ImportRecordBuilder()
    let existing = try builder.buildRecord(
      from: .fixture(
        text: "same",
        lastCopiedAt: 10,
        copyCount: 2,
        groupNames: ["Current"],
        pasteboardTypes: ["existing.type"]
      ),
      groupIDs: ["current"]
    )
    _ = try await store.importRecord(existing)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    do {
      _ = try await service.importRecords([
        .fixture(
          text: "same",
          lastCopiedAt: 20,
          sourceRecordID: "replacement-fails",
          copyCount: 5,
          groupNames: ["Imported Group"],
          pinned: true,
          pasteboardTypes: ["imported.type"]
        )
      ], batchSize: 1)
      XCTFail("Expected replacement payload save failure to throw")
    } catch {
      let records = try await store.fetchAll()
      XCTAssertEqual(records.count, 1)
      let record = try XCTUnwrap(records.first)
      XCTAssertEqual(record.id, existing.id)
      XCTAssertEqual(record.lastCopiedAt, existing.lastCopiedAt)
      XCTAssertEqual(record.copyCount, existing.copyCount)
      XCTAssertEqual(record.groupIds, ["current"])
      XCTAssertEqual(record.pasteboardTypes, ["existing.type"])
      XCTAssertFalse(record.isPinned)

      let written = try await readOnlyReport()
      XCTAssertEqual(written.status, .failed)
      XCTAssertEqual(written.failed, 1)
      XCTAssertEqual(written.committedBatchCount, 0)
      XCTAssertEqual(written.failures.count, 1)
      XCTAssertEqual(written.failures.first?.sourceRecordID, "replacement-fails")
      XCTAssertEqual(written.failures.first?.source, .clipasteCloud)
      XCTAssertTrue(written.failures.first?.reason.contains("payload unavailable") ?? false)
    }
  }

  func testReplacementHistoryFailureAfterPayloadSaveRestoresOldPayloadAndWritesFailedReport() async throws {
    let builder = ImportRecordBuilder()
    let existing = try builder.buildRecord(
      from: .fixture(
        text: "same",
        lastCopiedAt: 10,
        copyCount: 2,
        groupNames: ["Current"],
        pasteboardTypes: ["existing.type"]
      ),
      groupIDs: ["current"]
    )
    let store = FailingImportHistoryStore(existing: existing)
    let payloads = InMemoryPayloadStore()
    try await payloads.save(.text("old payload"), for: existing.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    do {
      _ = try await service.importRecords([
        .fixture(
          text: "same",
          lastCopiedAt: 20,
          sourceRecordID: "replacement-history-fails",
          copyCount: 5,
          groupNames: ["Imported Group"],
          pinned: true,
          pasteboardTypes: ["imported.type"]
        )
      ], batchSize: 1)
      XCTFail("Expected replacement history import failure to throw")
    } catch {
      let attemptedIDs = await store.attemptedImportRecordIDs()
      XCTAssertEqual(attemptedIDs, [existing.id])
      let records = try await store.fetchAll()
      XCTAssertEqual(records, [existing])
      let payload = try await payloads.loadPayload(for: existing.id)
      XCTAssertEqual(payload, .text("old payload"))
      let written = try await readOnlyReport()
      XCTAssertEqual(written.status, .failed)
      XCTAssertEqual(written.failed, 1)
      XCTAssertEqual(written.failures.count, 1)
      XCTAssertEqual(written.failures.first?.sourceRecordID, "replacement-history-fails")
      XCTAssertTrue(written.failures.first?.reason.contains("history import unavailable") ?? false)
    }
  }

  func testReplacementHistoryFailureReportsRollbackFailureWhenOldPayloadRestoreFails() async throws {
    let builder = ImportRecordBuilder()
    let existing = try builder.buildRecord(
      from: .fixture(text: "same", lastCopiedAt: 10),
      groupIDs: ["current"]
    )
    let store = FailingImportHistoryStore(existing: existing)
    let payloads = FailingRestorePayloadStore(recordID: existing.id, oldPayload: .text("old payload"))

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    do {
      _ = try await service.importRecords([
        .fixture(text: "same", lastCopiedAt: 20, sourceRecordID: "rollback-fails")
      ], batchSize: 1)
      XCTFail("Expected replacement history import failure to throw")
    } catch {
      let payload = try await payloads.loadPayload(for: existing.id)
      XCTAssertEqual(payload, .text("same"))
      let written = try await readOnlyReport()
      XCTAssertEqual(written.status, .failed)
      XCTAssertEqual(written.failed, 1)
      XCTAssertEqual(written.failures.first?.sourceRecordID, "rollback-fails")
      let reason = written.failures.first?.reason ?? ""
      XCTAssertTrue(reason.contains("history import unavailable"))
      XCTAssertTrue(reason.contains("rollback payload unavailable"))
    }
  }

  func testOlderImportedDuplicateMergesUniversalClipboardHintWithoutReplacingPayload() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let builder = ImportRecordBuilder()
    let newer = try builder.buildRecord(
      from: .fixture(text: "same", lastCopiedAt: 20),
      groupIDs: []
    )
    _ = try await store.importRecord(newer)
    try await payloads.save(.text("current payload"), for: newer.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let report = try await service.importRecords([
      .fixture(
        text: "same",
        lastCopiedAt: 10,
        sourceDeviceHint: .universalClipboard
      )
    ], batchSize: 1)

    XCTAssertEqual(report.merged, 1)
    let records = try await store.fetchAll()
    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(record.id, newer.id)
    XCTAssertEqual(record.sourceDeviceHint, .universalClipboard)
    let payload = try await payloads.loadPayload(for: newer.id)
    XCTAssertEqual(payload, .text("current payload"))
  }

  func testNewestImportReplacesOlderExistingAndMergesMetadataPreservingID() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let builder = ImportRecordBuilder()
    let older = try builder.buildRecord(
      from: .fixture(
        text: "same",
        lastCopiedAt: 10,
        copyCount: 2,
        groupNames: ["Current"],
        pasteboardTypes: ["existing.type"]
      ),
      groupIDs: ["current"]
    )
    _ = try await store.importRecord(older)
    try await payloads.save(.text("old payload"), for: older.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let report = try await service.importRecords([
      .fixture(
        text: "same",
        lastCopiedAt: 20,
        copyCount: 5,
        groupNames: ["Clipaste Import"],
        pinned: true,
        favorite: true,
        pasteboardTypes: ["imported.type"]
      )
    ])

    XCTAssertEqual(report.status, .completed)
    XCTAssertEqual(report.replacedByNewest, 1)
    let records = try await store.fetchAll()
    XCTAssertEqual(records.count, 1)
    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(record.id, older.id)
    XCTAssertEqual(record.lastCopiedAt, Date(timeIntervalSince1970: 20))
    XCTAssertEqual(record.copyCount, 7)
    XCTAssertEqual(Set(record.groupIds), ["current", "clipaste-import"])
    XCTAssertTrue(record.isPinned)
    XCTAssertTrue(record.isFavorite)
    XCTAssertTrue(record.retentionExempt)
    XCTAssertEqual(record.pasteboardTypes, ["existing.type", "imported.type"])
    let savedPayload = try await payloads.loadPayload(for: older.id)
    XCTAssertEqual(savedPayload, .text("same"))
  }

  func testNewestImportReplacementPreservesExistingCreatedAtWhenImportedCreatedAtIsEarlier() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let builder = ImportRecordBuilder()
    let existingCreatedAt = Date(timeIntervalSince1970: 50)
    let older = try builder.buildRecord(
      from: .fixture(
        text: "same",
        createdAt: 50,
        lastCopiedAt: 100,
        copyCount: 2,
        groupNames: ["Current"]
      ),
      groupIDs: ["current"]
    )
    _ = try await store.importRecord(older)
    try await payloads.save(.text("old payload"), for: older.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let report = try await service.importRecords([
      .fixture(
        text: "same",
        createdAt: 10,
        lastCopiedAt: 200,
        sourceRecordID: "newer-import",
        copyCount: 3,
        groupNames: ["Imported Group"],
        pinned: true
      )
    ], batchSize: 1)

    XCTAssertEqual(report.replacedByNewest, 1)
    let records = try await store.fetchAll()
    XCTAssertEqual(records.count, 1)
    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(record.id, older.id)
    XCTAssertEqual(record.createdAt, existingCreatedAt)
    XCTAssertEqual(record.lastCopiedAt, Date(timeIntervalSince1970: 200))
    XCTAssertEqual(record.title, "same")
    XCTAssertTrue(record.isPinned)
    let savedPayload = try await payloads.loadPayload(for: older.id)
    XCTAssertEqual(savedPayload, .text("same"))
  }

  func testOlderImportedDuplicateMergesMetadataWithoutReplacingPayload() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let builder = ImportRecordBuilder()
    let newer = try builder.buildRecord(
      from: .fixture(text: "same", lastCopiedAt: 20, copyCount: 3, groupNames: ["Current"]),
      groupIDs: ["current"]
    )
    _ = try await store.importRecord(newer)
    try await payloads.save(.text("current payload"), for: newer.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let report = try await service.importRecords([
      .fixture(
        text: "same",
        lastCopiedAt: 10,
        copyCount: 4,
        groupNames: ["Older Import"],
        pinned: true,
        pasteboardTypes: ["older.type"]
      )
    ])

    XCTAssertEqual(report.status, .completed)
    XCTAssertEqual(report.merged, 1)
    let storedRecords = try await store.fetchAll()
    let record = try XCTUnwrap(storedRecords.first)
    XCTAssertEqual(record.id, newer.id)
    XCTAssertEqual(record.lastCopiedAt, Date(timeIntervalSince1970: 20))
    XCTAssertEqual(record.copyCount, 7)
    XCTAssertEqual(Set(record.groupIds), ["current", "older-import"])
    XCTAssertTrue(record.isPinned)
    XCTAssertEqual(record.pasteboardTypes, ["public.utf8-plain-text", "older.type"])
    let savedPayload = try await payloads.loadPayload(for: newer.id)
    XCTAssertEqual(savedPayload, .text("current payload"))
  }

  func testCreatedGroupIDsForDuplicateOnlyIncludesGroupsIntroducedByImport() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let builder = ImportRecordBuilder()
    let existing = try builder.buildRecord(
      from: .fixture(text: "same", lastCopiedAt: 20, groupNames: ["Current"]),
      groupIDs: ["current"]
    )
    _ = try await store.importRecord(existing)
    try await payloads.save(.text("current payload"), for: existing.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let report = try await service.importRecords([
      .fixture(text: "same", lastCopiedAt: 10, groupNames: ["Current", "New Group"])
    ])

    XCTAssertEqual(report.merged, 1)
    XCTAssertEqual(report.createdGroupIDs, ["new-group"])
  }

  func testCancellationKeepsCommittedBatchDropsCurrentBatchAndWritesCancelledReport() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let records = [
      ImportedRecord.fixture(text: "one", lastCopiedAt: 1),
      ImportedRecord.fixture(text: "two", lastCopiedAt: 2),
      ImportedRecord.fixture(text: "three", lastCopiedAt: 3)
    ]

    let report = try await service.importRecords(records, batchSize: 1) { progress in
      progress.committedBatchCount >= 1
    }

    XCTAssertEqual(report.status, .cancelled)
    XCTAssertEqual(report.committedBatchCount, 1)
    let count = try await store.count()
    let storedRecords = try await store.fetchAll()
    XCTAssertEqual(count, 1)
    XCTAssertEqual(storedRecords.first?.title, "one")
    XCTAssertEqual(report.skipped, 1)
    let written = try await readOnlyReport()
    XCTAssertEqual(written.status, .cancelled)
    XCTAssertEqual(written.committedBatchCount, 1)
  }

  func testReportJSONWrittenOnCompletedImport() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    let report = try await service.importRecords([
      .fixture(text: "reported", lastCopiedAt: 1, warnings: ["unsupported type"])
    ])

    let written = try await readOnlyReport()
    XCTAssertEqual(written.id, report.id)
    XCTAssertEqual(written.status, .completed)
    XCTAssertEqual(written.imported, 1)
    XCTAssertEqual(written.warnings, ["unsupported type"])
  }

  func testGroupIDNormalizationIsDeterministicForImportedGroupNames() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)

    _ = try await service.importRecords([
      .fixture(text: "a", lastCopiedAt: 1, groupNames: ["Work Items"]),
      .fixture(text: "b", lastCopiedAt: 2, groupNames: [" work---items "]),
      .fixture(text: "c", lastCopiedAt: 3, groupNames: ["研发 分组"])
    ])

    let records = try await store.fetchAll()
    XCTAssertEqual(records.first { $0.title == "a" }?.groupIds, ["work-items"])
    XCTAssertEqual(records.first { $0.title == "b" }?.groupIds, ["work-items"])
    XCTAssertEqual(records.first { $0.title == "c" }?.groupIds, ["研发-分组"])
  }

  func testApplicationSupportPathsPrepareCreatesImportReportsDirectory() throws {
    let paths = try ApplicationSupportPaths(bundleIdentifier: "test.bundle", customBase: tempDir)

    try paths.prepare()

    XCTAssertTrue(paths.importReportsDirectory.path.hasSuffix("/imports/reports"))
    var isDirectory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: paths.importReportsDirectory.path, isDirectory: &isDirectory))
    XCTAssertTrue(isDirectory.boolValue)
  }

  private func readOnlyReport() async throws -> ImportReport {
    let files = try FileManager.default.contentsOfDirectory(
      at: tempDir,
      includingPropertiesForKeys: nil
    )
    let json = try XCTUnwrap(files.singleJSONReport)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(ImportReport.self, from: Data(contentsOf: json))
  }
}

private struct FailingPayloadStore: ClipboardPayloadStore {
  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    throw StorageError.underlying("payload unavailable")
  }

  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    nil
  }

  func delete(for recordID: UUID) async throws {}
}

private actor FailingDeletePayloadStore: ClipboardPayloadStore {
  private var payloadsByRecordID: [UUID: ClipboardPayload] = [:]

  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    payloadsByRecordID[recordID] = payload
  }

  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    payloadsByRecordID[recordID]
  }

  func delete(for recordID: UUID) async throws {
    throw StorageError.underlying("payload delete unavailable")
  }
}

private actor FailingImportHistoryStore: ImportWritableHistoryStore {
  private var recordsByHash: [String: ClipboardRecord]
  private var attemptedIDs: [UUID] = []

  init(existing: ClipboardRecord? = nil) {
    if let existing {
      recordsByHash = [existing.contentHash: existing]
    } else {
      recordsByHash = [:]
    }
  }

  func attemptedImportRecordIDs() -> [UUID] {
    attemptedIDs
  }

  func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    recordsByHash[hash]
  }

  func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    attemptedIDs.append(record.id)
    throw StorageError.underlying("history import unavailable")
  }

  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    try await importRecord(record)
  }

  func fetchAll() async throws -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord] {
    let all = try await fetchAll()
    return Array(all.filter { query.matches($0) }.prefix(max(0, limit)))
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

private actor FailingRestorePayloadStore: ClipboardPayloadStore {
  private let recordID: UUID
  private var payload: ClipboardPayload
  private var saveCount = 0

  init(recordID: UUID, oldPayload: ClipboardPayload) {
    self.recordID = recordID
    self.payload = oldPayload
  }

  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    guard recordID == self.recordID else { return }
    saveCount += 1
    if saveCount == 1 {
      self.payload = payload
    } else {
      throw StorageError.underlying("rollback payload unavailable")
    }
  }

  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    recordID == self.recordID ? payload : nil
  }

  func delete(for recordID: UUID) async throws {
    if recordID == self.recordID {
      throw StorageError.underlying("rollback payload unavailable")
    }
  }
}

private extension Array where Element == URL {
  var singleJSONReport: URL? {
    filter { $0.pathExtension == "json" }.first
  }
}

private extension ImportedRecord {
  static func fixture(
    text: String,
    createdAt: TimeInterval? = nil,
    lastCopiedAt: TimeInterval,
    sourceRecordID: String? = nil,
    copyCount: Int = 1,
    groupNames: [String] = ["Clipaste Import"],
    pinned: Bool = false,
    favorite: Bool = false,
    sourceDeviceHint: ClipboardSourceDeviceHint = .imported,
    pasteboardTypes: Set<String> = ["public.utf8-plain-text"],
    warnings: [String] = []
  ) -> ImportedRecord {
    ImportedRecord(
      source: .clipasteCloud,
      sourceRecordID: sourceRecordID ?? text,
      payload: .text(text),
      primaryType: text.hasPrefix("http") ? .link : .text,
      pasteboardTypes: pasteboardTypes,
      title: text,
      plainTextPreview: text,
      sourceAppBundleId: nil,
      sourceAppName: nil,
      createdAt: Date(timeIntervalSince1970: createdAt ?? lastCopiedAt),
      lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
      copyCount: copyCount,
      isPinned: pinned,
      isFavorite: favorite,
      groupNames: groupNames,
      sourceDeviceHint: sourceDeviceHint,
      externalContentHash: nil,
      warnings: warnings
    )
  }
}
