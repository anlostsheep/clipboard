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
      sourceDeviceHint: .imported,
      externalContentHash: nil,
      warnings: warnings
    )
  }
}
