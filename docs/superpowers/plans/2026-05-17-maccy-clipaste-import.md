# Maccy Clipaste Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a high-fidelity Maccy and Clipaste history import feature that discovers installed stores, supports manual database selection, imports through snapshots, preserves supported payloads and metadata, deduplicates by newest time, and writes a report.

**Architecture:** Add a focused import subsystem under `ClipboardCore/Import` and a thin Settings Import page in `ClipboardApp`. Parsers only read external stores and emit `ImportedRecord`; `ImportService` owns deduplication, batch writes, cancellation, and reports. Storage gets a narrow import-write protocol so import can replace a full record without changing normal clipboard ingest semantics.

**Tech Stack:** Swift 5.10, Swift Concurrency, SQLite3 C API through the existing `SQLiteConnection` wrapper, SwiftUI Settings UI, XCTest.

---

## File Structure

- Create `Sources/ClipboardCore/Import/ImportedRecord.swift`
  - Defines source identifiers, source candidates, parser output, import warnings, and progress/report DTOs.
- Create `Sources/ClipboardCore/Import/ImportRecordBuilder.swift`
  - Converts `ImportedRecord` plus merged metadata into `ClipboardRecord`.
  - Computes the current app content hash from the final payload.
- Create `Sources/ClipboardCore/Import/ImportSourceDiscovery.swift`
  - Finds standard Maccy and Clipaste stores.
  - Classifies manual SQLite/SwiftData store files by schema.
- Create `Sources/ClipboardCore/Import/ImportSnapshotService.swift`
  - Copies selected database and same-prefix `-wal` / `-shm` sidecars into a temporary directory.
- Create `Sources/ClipboardCore/Import/ExternalSQLiteDatabase.swift`
  - Opens source snapshots read-only and exposes table/column checks, scalar queries, text/blob/date accessors, and row iteration.
- Create `Sources/ClipboardCore/Import/MaccyImporter.swift`
  - Reads `ZHISTORYITEM` and `ZHISTORYITEMCONTENT` and emits `ImportedRecord`.
- Create `Sources/ClipboardCore/Import/ClipasteImporter.swift`
  - Reads `ZCLIPBOARDRECORD` and `ZCLIPBOARDGROUPMODEL` and emits `ImportedRecord`.
- Create `Sources/ClipboardCore/Import/ImportService.swift`
  - Runs preflight, import, newest-time dedupe, batch commit, cancellation, and report writing.
- Modify `Sources/ClipboardCore/Storage/HistoryStore.swift`
  - Add `ImportWritableHistoryStore` and in-memory conformance.
- Modify `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
  - Add full-record import replacement without `upsert` copy-count semantics.
- Modify `Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift`
  - Forward import-write calls to the wrapped store.
- Modify `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`
  - Forward import-write calls with existing disk-full recovery behavior.
- Modify `Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift`
  - Add read-only opening and blob column reading needed by source importers.
- Modify `Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift`
  - Add `imports/reports` directory path.
- Modify `Sources/ClipboardApp/AppServices.swift`
  - Construct and expose `ImportService`.
- Modify `Sources/ClipboardApp/Settings/SettingsWindow.swift`
  - Add Import tab.
- Create `Sources/ClipboardApp/Settings/ImportSettingsView.swift`
  - Settings UI for discovery, manual source selection, preflight, progress, cancellation, and latest report.
- Create tests:
  - `Tests/ClipboardCoreTests/ImportRecordBuilderTests.swift`
  - `Tests/ClipboardCoreTests/ImportSourceDiscoveryTests.swift`
  - `Tests/ClipboardCoreTests/ImportSnapshotServiceTests.swift`
  - `Tests/ClipboardCoreTests/MaccyImporterTests.swift`
  - `Tests/ClipboardCoreTests/ClipasteImporterTests.swift`
  - `Tests/ClipboardCoreTests/ImportServiceTests.swift`
  - `Tests/ClipboardAppTests/ImportSettingsViewTests.swift`

---

### Task 1: Core Import DTOs And Hash Builder

**Files:**
- Create: `Sources/ClipboardCore/Import/ImportedRecord.swift`
- Create: `Sources/ClipboardCore/Import/ImportRecordBuilder.swift`
- Test: `Tests/ClipboardCoreTests/ImportRecordBuilderTests.swift`

- [ ] **Step 1: Write failing tests for current-app hashing and record construction**

Create `Tests/ClipboardCoreTests/ImportRecordBuilderTests.swift`:

```swift
import XCTest
@testable import ClipboardCore

final class ImportRecordBuilderTests: XCTestCase {
  func testBuildTextRecordComputesStableCurrentAppHash() throws {
    let imported = ImportedRecord(
      source: .maccy,
      sourceRecordID: "42",
      payload: .text("https://example.com/a"),
      primaryType: .link,
      pasteboardTypes: ["public.utf8-plain-text"],
      title: "Example",
      plainTextPreview: "https://example.com/a",
      sourceAppBundleId: "com.apple.Safari",
      sourceAppName: "Safari",
      createdAt: Date(timeIntervalSince1970: 10),
      lastCopiedAt: Date(timeIntervalSince1970: 20),
      copyCount: 3,
      isPinned: true,
      isFavorite: false,
      groupNames: ["Maccy Import"],
      sourceDeviceHint: .imported,
      externalContentHash: "external",
      warnings: []
    )

    let first = try ImportRecordBuilder().buildRecord(from: imported, groupIDs: ["maccy-import"])
    let second = try ImportRecordBuilder().buildRecord(from: imported, groupIDs: ["maccy-import"])

    XCTAssertEqual(first.contentHash, second.contentHash)
    XCTAssertEqual(first.primaryType, .link)
    XCTAssertEqual(first.title, "Example")
    XCTAssertEqual(first.copyCount, 3)
    XCTAssertEqual(first.isPinned, true)
    XCTAssertEqual(first.groupIds, ["maccy-import"])
    XCTAssertEqual(first.sourceDeviceHint, .imported)
    XCTAssertEqual(first.pasteboardTypes, ["public.utf8-plain-text"])
  }

  func testBuildImageRecordHashesImageDataNotTitle() throws {
    let first = ImportedRecord.fixture(
      payload: .image(data: Data([1, 2, 3]), uti: "public.png"),
      primaryType: .image,
      title: "A"
    )
    let second = ImportedRecord.fixture(
      payload: .image(data: Data([1, 2, 3]), uti: "public.png"),
      primaryType: .image,
      title: "B"
    )

    let a = try ImportRecordBuilder().buildRecord(from: first, groupIDs: [])
    let b = try ImportRecordBuilder().buildRecord(from: second, groupIDs: [])

    XCTAssertEqual(a.contentHash, b.contentHash)
  }
}

private extension ImportedRecord {
  static func fixture(
    payload: ClipboardPayload = .text("hello"),
    primaryType: ClipboardContentType = .text,
    title: String = "hello"
  ) -> ImportedRecord {
    ImportedRecord(
      source: .clipasteCloud,
      sourceRecordID: "fixture",
      payload: payload,
      primaryType: primaryType,
      pasteboardTypes: [],
      title: title,
      plainTextPreview: title,
      sourceAppBundleId: nil,
      sourceAppName: nil,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupNames: [],
      sourceDeviceHint: .imported,
      externalContentHash: nil,
      warnings: []
    )
  }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter ImportRecordBuilderTests
```

Expected:

```text
error: cannot find 'ImportedRecord' in scope
```

- [ ] **Step 3: Add import DTOs**

Create `Sources/ClipboardCore/Import/ImportedRecord.swift` with these public types:

```swift
import Foundation

public enum ImportSourceKind: String, Codable, Equatable, Sendable {
  case maccy
  case clipasteCloud
  case clipasteLocal
  case manualMaccy
  case manualClipaste
}

public enum ImportSchemaKind: String, Codable, Equatable, Sendable {
  case maccy
  case clipaste
  case unknown
}

public enum ImportReportStatus: String, Codable, Equatable, Sendable {
  case completed
  case cancelled
  case failed
}

public struct ImportSourceCandidate: Identifiable, Equatable, Sendable {
  public let id: String
  public let kind: ImportSourceKind
  public let displayName: String
  public let databaseURL: URL
  public let appBundleID: String?
  public let appVersion: String?
  public let storeSizeBytes: Int64
  public let recordCount: Int?
  public let typeDistribution: [String: Int]
  public let lastModifiedAt: Date?
  public let schemaKind: ImportSchemaKind
  public let schemaStatus: String
  public let isDefaultSelected: Bool

  public init(
    id: String,
    kind: ImportSourceKind,
    displayName: String,
    databaseURL: URL,
    appBundleID: String?,
    appVersion: String?,
    storeSizeBytes: Int64,
    recordCount: Int?,
    typeDistribution: [String: Int],
    lastModifiedAt: Date?,
    schemaKind: ImportSchemaKind,
    schemaStatus: String,
    isDefaultSelected: Bool
  ) {
    self.id = id
    self.kind = kind
    self.displayName = displayName
    self.databaseURL = databaseURL
    self.appBundleID = appBundleID
    self.appVersion = appVersion
    self.storeSizeBytes = storeSizeBytes
    self.recordCount = recordCount
    self.typeDistribution = typeDistribution
    self.lastModifiedAt = lastModifiedAt
    self.schemaKind = schemaKind
    self.schemaStatus = schemaStatus
    self.isDefaultSelected = isDefaultSelected
  }
}

public struct ImportedRecord: Equatable, Sendable {
  public let source: ImportSourceKind
  public let sourceRecordID: String
  public let payload: ClipboardPayload
  public let primaryType: ClipboardContentType
  public let pasteboardTypes: Set<String>
  public let title: String
  public let plainTextPreview: String?
  public let sourceAppBundleId: String?
  public let sourceAppName: String?
  public let createdAt: Date
  public let lastCopiedAt: Date
  public let copyCount: Int
  public let isPinned: Bool
  public let isFavorite: Bool
  public let groupNames: [String]
  public let sourceDeviceHint: ClipboardSourceDeviceHint
  public let externalContentHash: String?
  public let warnings: [String]

  public init(
    source: ImportSourceKind,
    sourceRecordID: String,
    payload: ClipboardPayload,
    primaryType: ClipboardContentType,
    pasteboardTypes: Set<String>,
    title: String,
    plainTextPreview: String?,
    sourceAppBundleId: String?,
    sourceAppName: String?,
    createdAt: Date,
    lastCopiedAt: Date,
    copyCount: Int,
    isPinned: Bool,
    isFavorite: Bool,
    groupNames: [String],
    sourceDeviceHint: ClipboardSourceDeviceHint,
    externalContentHash: String?,
    warnings: [String]
  ) {
    self.source = source
    self.sourceRecordID = sourceRecordID
    self.payload = payload
    self.primaryType = primaryType
    self.pasteboardTypes = pasteboardTypes
    self.title = title
    self.plainTextPreview = plainTextPreview
    self.sourceAppBundleId = sourceAppBundleId
    self.sourceAppName = sourceAppName
    self.createdAt = createdAt
    self.lastCopiedAt = lastCopiedAt
    self.copyCount = max(1, copyCount)
    self.isPinned = isPinned
    self.isFavorite = isFavorite
    self.groupNames = groupNames
    self.sourceDeviceHint = sourceDeviceHint
    self.externalContentHash = externalContentHash
    self.warnings = warnings
  }
}

public struct ImportFailure: Codable, Equatable, Sendable {
  public let source: ImportSourceKind
  public let sourceRecordID: String?
  public let titleOrPreview: String?
  public let reason: String
}

public struct ImportReport: Codable, Equatable, Sendable {
  public var id: UUID
  public var createdAt: Date
  public var status: ImportReportStatus
  public var sources: [String]
  public var schemaVersions: [String: String]
  public var scanned: Int
  public var imported: Int
  public var merged: Int
  public var replacedByNewest: Int
  public var skipped: Int
  public var failed: Int
  public var committedBatchCount: Int
  public var lastProcessedSourceRecordID: String?
  public var createdGroupIDs: [String]
  public var warnings: [String]
  public var failures: [ImportFailure]
  public var duration: TimeInterval
  public var appVersion: String
  public var reportSchemaVersion: Int

  public init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    status: ImportReportStatus,
    sources: [String],
    schemaVersions: [String: String] = [:],
    scanned: Int = 0,
    imported: Int = 0,
    merged: Int = 0,
    replacedByNewest: Int = 0,
    skipped: Int = 0,
    failed: Int = 0,
    committedBatchCount: Int = 0,
    lastProcessedSourceRecordID: String? = nil,
    createdGroupIDs: [String] = [],
    warnings: [String] = [],
    failures: [ImportFailure] = [],
    duration: TimeInterval = 0,
    appVersion: String = "unknown",
    reportSchemaVersion: Int = 1
  ) {
    self.id = id
    self.createdAt = createdAt
    self.status = status
    self.sources = sources
    self.schemaVersions = schemaVersions
    self.scanned = scanned
    self.imported = imported
    self.merged = merged
    self.replacedByNewest = replacedByNewest
    self.skipped = skipped
    self.failed = failed
    self.committedBatchCount = committedBatchCount
    self.lastProcessedSourceRecordID = lastProcessedSourceRecordID
    self.createdGroupIDs = createdGroupIDs
    self.warnings = warnings
    self.failures = failures
    self.duration = duration
    self.appVersion = appVersion
    self.reportSchemaVersion = reportSchemaVersion
  }
}
```

- [ ] **Step 4: Add content hash builder**

Create `Sources/ClipboardCore/Import/ImportRecordBuilder.swift`:

```swift
import CryptoKit
import Foundation

public struct ImportRecordBuilder: Sendable {
  public init() {}

  public func buildRecord(from imported: ImportedRecord, groupIDs: [String]) throws -> ClipboardRecord {
    ClipboardRecord(
      id: UUID(),
      contentHash: contentHash(for: imported.payload),
      primaryType: imported.primaryType,
      title: normalizedTitle(imported.title, fallback: imported.plainTextPreview, type: imported.primaryType),
      plainTextPreview: imported.plainTextPreview,
      sourceAppBundleId: imported.sourceAppBundleId,
      sourceAppName: imported.sourceAppName,
      sourceDeviceHint: imported.sourceDeviceHint,
      createdAt: imported.createdAt,
      lastCopiedAt: imported.lastCopiedAt,
      copyCount: max(1, imported.copyCount),
      isPinned: imported.isPinned,
      isFavorite: imported.isFavorite,
      groupIds: groupIDs,
      retentionExempt: imported.isPinned || imported.isFavorite,
      metadata: nil,
      pasteboardTypes: imported.pasteboardTypes
    )
  }

  public func contentHash(for payload: ClipboardPayload) -> String {
    switch payload {
    case .text(let text):
      return hash(Data(text.utf8))
    case .richText(let plainText, let rtfData):
      var data = Data("richText\0".utf8)
      data.append(Data(plainText.utf8))
      data.append(0)
      data.append(rtfData)
      return hash(data)
    case .image(let data, _):
      return hash(data)
    case .fileURLs(let urls):
      return hash(Data(urls.map(\.absoluteString).joined(separator: "\n").utf8))
    }
  }

  private func normalizedTitle(_ title: String, fallback: String?, type: ClipboardContentType) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return String(trimmed.prefix(120)) }
    if let fallback, !fallback.isEmpty { return String(fallback.prefix(120)) }
    switch type {
    case .text: return "Text"
    case .richText: return "Rich Text"
    case .link: return "Link"
    case .image: return "Image"
    case .file: return "Files"
    }
  }

  private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --filter ImportRecordBuilderTests
```

Expected:

```text
Test Suite 'ImportRecordBuilderTests' passed
```

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/ClipboardCore/Import/ImportedRecord.swift Sources/ClipboardCore/Import/ImportRecordBuilder.swift Tests/ClipboardCoreTests/ImportRecordBuilderTests.swift
git commit -m "feat: add import record model"
```

---

### Task 2: External SQLite Reader And Snapshot Service

**Files:**
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift`
- Create: `Sources/ClipboardCore/Import/ExternalSQLiteDatabase.swift`
- Create: `Sources/ClipboardCore/Import/ImportSnapshotService.swift`
- Test: `Tests/ClipboardCoreTests/ImportSnapshotServiceTests.swift`

- [ ] **Step 1: Write failing snapshot and read-only SQLite tests**

Create `Tests/ClipboardCoreTests/ImportSnapshotServiceTests.swift`:

```swift
import SQLite3
import XCTest
@testable import ClipboardCore

final class ImportSnapshotServiceTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-import-snapshot-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testSnapshotCopiesDatabaseAndSidecars() throws {
    let db = tempDir.appendingPathComponent("source.sqlite")
    try Data("sqlite".utf8).write(to: db)
    try Data("wal".utf8).write(to: tempDir.appendingPathComponent("source.sqlite-wal"))
    try Data("shm".utf8).write(to: tempDir.appendingPathComponent("source.sqlite-shm"))

    let snapshot = try ImportSnapshotService().snapshot(databaseURL: db)

    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.databaseURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.databaseURL.path + "-wal"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.databaseURL.path + "-shm"))
    XCTAssertNotEqual(snapshot.databaseURL.deletingLastPathComponent(), db.deletingLastPathComponent())
  }

  func testExternalDatabaseDetectsTablesAndColumns() throws {
    let db = tempDir.appendingPathComponent("fixture.sqlite")
    try createSQLiteFixture(at: db)

    let external = try ExternalSQLiteDatabase(path: db.path)

    XCTAssertTrue(try external.hasTable("ZHISTORYITEM"))
    XCTAssertTrue(try external.hasColumns(["Z_PK", "ZTITLE"], in: "ZHISTORYITEM"))
    XCTAssertEqual(try external.intScalar("SELECT COUNT(*) FROM ZHISTORYITEM"), 1)
  }

  private func createSQLiteFixture(at url: URL) throws {
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT)", nil, nil, nil), SQLITE_OK)
    XCTAssertEqual(sqlite3_exec(db, "INSERT INTO ZHISTORYITEM (Z_PK, ZTITLE) VALUES (1, 'hello')", nil, nil, nil), SQLITE_OK)
  }
}
```

- [ ] **Step 2: Run snapshot tests and verify failure**

Run:

```bash
swift test --filter ImportSnapshotServiceTests
```

Expected:

```text
error: cannot find 'ImportSnapshotService' in scope
```

- [ ] **Step 3: Add read-only SQLite support and blob access**

Modify `Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift`:

```swift
  init(path: String, readOnly: Bool = false) throws {
    var handle: OpaquePointer?
    let flags = (readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)) | SQLITE_OPEN_FULLMUTEX
    let rc = sqlite3_open_v2(path, &handle, flags, nil)
    guard rc == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw StorageError.underlying("sqlite3_open_v2 rc=\(rc)")
    }
    self.db = handle
  }
```

Add this method to `Statement`:

```swift
  func columnData(_ index: Int32) -> Data? {
    guard let bytes = sqlite3_column_blob(handle, index) else { return nil }
    let count = Int(sqlite3_column_bytes(handle, index))
    return Data(bytes: bytes, count: count)
  }
```

- [ ] **Step 4: Add external database wrapper**

Create `Sources/ClipboardCore/Import/ExternalSQLiteDatabase.swift`:

```swift
import Foundation
import SQLite3

public final class ExternalSQLiteDatabase: @unchecked Sendable {
  private let connection: SQLiteConnection

  public init(path: String) throws {
    self.connection = try SQLiteConnection(path: path, readOnly: true)
  }

  public func hasTable(_ table: String) throws -> Bool {
    let stmt = try connection.prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1")
    defer { stmt.finalize() }
    stmt.bindText(1, table)
    return try stmt.step() == SQLITE_ROW
  }

  public func columns(in table: String) throws -> Set<String> {
    let safeTable = try quoteIdentifier(table)
    let stmt = try connection.prepare("PRAGMA table_info(\(safeTable))")
    defer { stmt.finalize() }
    var result = Set<String>()
    while try stmt.step() == SQLITE_ROW {
      if let name = stmt.columnText(1) {
        result.insert(name)
      }
    }
    return result
  }

  public func hasColumns(_ required: Set<String>, in table: String) throws -> Bool {
    required.isSubset(of: try columns(in: table))
  }

  public func intScalar(_ sql: String) throws -> Int {
    try connection.intScalar(sql)
  }

  public func rows(_ sql: String, bind: ((Statement) -> Void)? = nil, read: (Statement) throws -> Void) throws {
    let stmt = try connection.prepare(sql)
    defer { stmt.finalize() }
    bind?(stmt)
    while try stmt.step() == SQLITE_ROW {
      try read(stmt)
    }
  }

  private func quoteIdentifier(_ value: String) throws -> String {
    guard value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
      throw StorageError.underlying("unsafe sqlite identifier \(value)")
    }
    return "\"\(value)\""
  }
}
```

- [ ] **Step 5: Add snapshot service**

Create `Sources/ClipboardCore/Import/ImportSnapshotService.swift`:

```swift
import Foundation

public struct ImportSnapshot: Sendable {
  public let databaseURL: URL
  public let directoryURL: URL
}

public struct ImportSnapshotService: Sendable {
  private let fileManager: FileManager

  public init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  public func snapshot(databaseURL: URL) throws -> ImportSnapshot {
    let base = fileManager.temporaryDirectory
      .appendingPathComponent("clipboard-import-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: base, withIntermediateDirectories: true)

    let target = base.appendingPathComponent(databaseURL.lastPathComponent)
    try fileManager.copyItem(at: databaseURL, to: target)

    for suffix in ["-wal", "-shm"] {
      let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
      if fileManager.fileExists(atPath: sidecar.path) {
        try fileManager.copyItem(at: sidecar, to: URL(fileURLWithPath: target.path + suffix))
      }
    }

    return ImportSnapshot(databaseURL: target, directoryURL: base)
  }
}
```

- [ ] **Step 6: Run focused tests**

Run:

```bash
swift test --filter ImportSnapshotServiceTests
```

Expected:

```text
Test Suite 'ImportSnapshotServiceTests' passed
```

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift Sources/ClipboardCore/Import/ExternalSQLiteDatabase.swift Sources/ClipboardCore/Import/ImportSnapshotService.swift Tests/ClipboardCoreTests/ImportSnapshotServiceTests.swift
git commit -m "feat: add import sqlite snapshots"
```

---

### Task 3: Source Discovery And Manual Classification

**Files:**
- Create: `Sources/ClipboardCore/Import/ImportSourceDiscovery.swift`
- Test: `Tests/ClipboardCoreTests/ImportSourceDiscoveryTests.swift`

- [ ] **Step 1: Write failing discovery tests with custom roots**

Create `Tests/ClipboardCoreTests/ImportSourceDiscoveryTests.swift`:

```swift
import SQLite3
import XCTest
@testable import ClipboardCore

final class ImportSourceDiscoveryTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-import-discovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testClassifiesManualMaccyBySchema() throws {
    let db = tempDir.appendingPathComponent("Storage.sqlite")
    try makeMaccySchema(at: db)

    let candidate = try ImportSourceDiscovery(homeDirectory: tempDir).classifyManualDatabase(db)

    XCTAssertEqual(candidate.schemaKind, .maccy)
    XCTAssertEqual(candidate.kind, .manualMaccy)
    XCTAssertEqual(candidate.recordCount, 0)
  }

  func testClassifiesManualClipasteBySchema() throws {
    let db = tempDir.appendingPathComponent("clipboard-cloud.store")
    try makeClipasteSchema(at: db)

    let candidate = try ImportSourceDiscovery(homeDirectory: tempDir).classifyManualDatabase(db)

    XCTAssertEqual(candidate.schemaKind, .clipaste)
    XCTAssertEqual(candidate.kind, .manualClipaste)
    XCTAssertEqual(candidate.recordCount, 0)
  }

  func testRejectsUnknownSQLiteSchema() throws {
    let db = tempDir.appendingPathComponent("unknown.sqlite")
    try createDB(at: db, sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY)")

    let candidate = try ImportSourceDiscovery(homeDirectory: tempDir).classifyManualDatabase(db)

    XCTAssertEqual(candidate.schemaKind, .unknown)
    XCTAssertEqual(candidate.schemaStatus, "Unsupported schema")
    XCTAssertFalse(candidate.isDefaultSelected)
  }

  private func makeMaccySchema(at url: URL) throws {
    try createDB(at: url, sql: """
      CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZFIRSTCOPIEDAT REAL, ZLASTCOPIEDAT REAL, ZNUMBEROFCOPIES INTEGER, ZAPPLICATION TEXT, ZPIN TEXT, ZTITLE TEXT);
      CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE TEXT, ZVALUE BLOB);
      """)
  }

  private func makeClipasteSchema(at url: URL) throws {
    try createDB(at: url, sql: """
      CREATE TABLE ZCLIPBOARDRECORD (Z_PK INTEGER PRIMARY KEY, ZID TEXT, ZTIMESTAMP REAL, ZTYPERAWVALUE TEXT, ZPLAINTEXT TEXT, ZCONTENTHASH TEXT, ZISPINNED INTEGER, ZGROUPID TEXT, ZGROUPIDSRAW TEXT);
      CREATE TABLE ZCLIPBOARDGROUPMODEL (Z_PK INTEGER PRIMARY KEY, ZID TEXT, ZNAME TEXT);
      """)
  }

  private func createDB(at url: URL, sql: String) throws {
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
  }
}
```

- [ ] **Step 2: Run discovery tests and verify failure**

Run:

```bash
swift test --filter ImportSourceDiscoveryTests
```

Expected:

```text
error: cannot find 'ImportSourceDiscovery' in scope
```

- [ ] **Step 3: Implement source discovery**

Create `Sources/ClipboardCore/Import/ImportSourceDiscovery.swift`:

```swift
import Foundation

public struct ImportSourceDiscovery: Sendable {
  private let homeDirectory: URL
  private let fileManager: FileManager

  public init(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()), fileManager: FileManager = .default) {
    self.homeDirectory = homeDirectory
    self.fileManager = fileManager
  }

  public func discoverAutomaticSources() -> [ImportSourceCandidate] {
    var candidates: [ImportSourceCandidate] = []
    if let maccy = try? candidate(
      kind: .maccy,
      displayName: "Maccy",
      databaseURL: homeDirectory.appendingPathComponent("Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"),
      appBundleID: "org.p0deje.Maccy",
      appURL: URL(fileURLWithPath: "/Applications/Maccy.app"),
      defaultSelected: true
    ), maccy.schemaKind == .maccy {
      candidates.append(maccy)
    }

    let clipasteCloudURL = homeDirectory.appendingPathComponent("Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-cloud.store")
    let clipasteLocalURL = homeDirectory.appendingPathComponent("Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-local.store")
    let cloud = try? candidate(kind: .clipasteCloud, displayName: "Clipaste Cloud", databaseURL: clipasteCloudURL, appBundleID: "com.gangz1o.clipaste", appURL: URL(fileURLWithPath: "/Applications/Clipaste.app"), defaultSelected: true)
    let local = try? candidate(kind: .clipasteLocal, displayName: "Clipaste Local", databaseURL: clipasteLocalURL, appBundleID: "com.gangz1o.clipaste", appURL: URL(fileURLWithPath: "/Applications/Clipaste.app"), defaultSelected: cloud?.schemaKind != .clipaste)
    if let cloud, cloud.schemaKind == .clipaste { candidates.append(cloud) }
    if let local, local.schemaKind == .clipaste { candidates.append(local) }
    return candidates
  }

  public func classifyManualDatabase(_ url: URL) throws -> ImportSourceCandidate {
    let schema = try schemaKind(for: url)
    let kind: ImportSourceKind
    switch schema {
    case .maccy: kind = .manualMaccy
    case .clipaste: kind = .manualClipaste
    case .unknown: kind = .manualMaccy
    }
    return try candidate(
      kind: kind,
      displayName: url.lastPathComponent,
      databaseURL: url,
      appBundleID: nil,
      appURL: nil,
      defaultSelected: schema != .unknown
    )
  }

  private func candidate(
    kind: ImportSourceKind,
    displayName: String,
    databaseURL: URL,
    appBundleID: String?,
    appURL: URL?,
    defaultSelected: Bool
  ) throws -> ImportSourceCandidate {
    guard fileManager.fileExists(atPath: databaseURL.path) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let schema = try schemaKind(for: databaseURL)
    let attrs = try? fileManager.attributesOfItem(atPath: databaseURL.path)
    let size = attrs?[.size] as? NSNumber
    let modified = attrs?[.modificationDate] as? Date
    let counts = try sourceCounts(databaseURL: databaseURL, schema: schema)
    let version = appURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }

    return ImportSourceCandidate(
      id: "\(kind.rawValue):\(databaseURL.path)",
      kind: kind,
      displayName: displayName,
      databaseURL: databaseURL,
      appBundleID: appBundleID,
      appVersion: version,
      storeSizeBytes: size?.int64Value ?? 0,
      recordCount: counts.count,
      typeDistribution: counts.distribution,
      lastModifiedAt: modified,
      schemaKind: schema,
      schemaStatus: schema == .unknown ? "Unsupported schema" : "OK",
      isDefaultSelected: defaultSelected && schema != .unknown
    )
  }

  private func schemaKind(for url: URL) throws -> ImportSchemaKind {
    let db = try ExternalSQLiteDatabase(path: url.path)
    if try db.hasTable("ZHISTORYITEM"),
       try db.hasTable("ZHISTORYITEMCONTENT"),
       try db.hasColumns(["Z_PK", "ZFIRSTCOPIEDAT", "ZLASTCOPIEDAT", "ZNUMBEROFCOPIES", "ZAPPLICATION", "ZPIN", "ZTITLE"], in: "ZHISTORYITEM"),
       try db.hasColumns(["Z_PK", "ZITEM", "ZTYPE", "ZVALUE"], in: "ZHISTORYITEMCONTENT") {
      return .maccy
    }
    if try db.hasTable("ZCLIPBOARDRECORD"),
       try db.hasColumns(["Z_PK", "ZTYPERAWVALUE"], in: "ZCLIPBOARDRECORD") {
      return .clipaste
    }
    return .unknown
  }

  private func sourceCounts(databaseURL: URL, schema: ImportSchemaKind) throws -> (count: Int?, distribution: [String: Int]) {
    let db = try ExternalSQLiteDatabase(path: databaseURL.path)
    switch schema {
    case .maccy:
      let count = try db.intScalar("SELECT COUNT(*) FROM ZHISTORYITEM")
      var distribution: [String: Int] = [:]
      try db.rows("SELECT ZTYPE, COUNT(*) FROM ZHISTORYITEMCONTENT GROUP BY ZTYPE") { stmt in
        if let type = stmt.columnText(0) {
          distribution[type] = stmt.columnInt(1)
        }
      }
      return (count, distribution)
    case .clipaste:
      let count = try db.intScalar("SELECT COUNT(*) FROM ZCLIPBOARDRECORD")
      var distribution: [String: Int] = [:]
      try db.rows("SELECT ZTYPERAWVALUE, COUNT(*) FROM ZCLIPBOARDRECORD GROUP BY ZTYPERAWVALUE") { stmt in
        if let type = stmt.columnText(0) {
          distribution[type] = stmt.columnInt(1)
        }
      }
      return (count, distribution)
    case .unknown:
      return (nil, [:])
    }
  }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter ImportSourceDiscoveryTests
```

Expected:

```text
Test Suite 'ImportSourceDiscoveryTests' passed
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/ClipboardCore/Import/ImportSourceDiscovery.swift Tests/ClipboardCoreTests/ImportSourceDiscoveryTests.swift
git commit -m "feat: discover import sources"
```

---

### Task 4: Maccy Importer

**Files:**
- Create: `Sources/ClipboardCore/Import/MaccyImporter.swift`
- Test: `Tests/ClipboardCoreTests/MaccyImporterTests.swift`

- [ ] **Step 1: Write failing Maccy fixture tests**

Create `Tests/ClipboardCoreTests/MaccyImporterTests.swift`:

```swift
import SQLite3
import XCTest
@testable import ClipboardCore

final class MaccyImporterTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-maccy-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testParsesTextLinkPinCopyCountAndUniversalClipboard() throws {
    let db = tempDir.appendingPathComponent("Storage.sqlite")
    try makeMaccyFixture(at: db)

    let records = try MaccyImporter(source: .maccy).importRecords(from: db)

    XCTAssertEqual(records.count, 2)
    let link = try XCTUnwrap(records.first { $0.sourceRecordID == "1" })
    XCTAssertEqual(link.payload, .text("https://example.com"))
    XCTAssertEqual(link.primaryType, .link)
    XCTAssertEqual(link.sourceAppBundleId, "com.apple.Safari")
    XCTAssertEqual(link.copyCount, 4)
    XCTAssertEqual(link.isPinned, true)
    XCTAssertEqual(link.sourceDeviceHint, .universalClipboard)
    XCTAssertEqual(link.groupNames, ["Maccy Import"])
    XCTAssertTrue(link.pasteboardTypes.contains("public.utf8-plain-text"))
  }

  func testPrefersRichPayloadOverTitleFallback() throws {
    let db = tempDir.appendingPathComponent("Storage.sqlite")
    try makeMaccyFixture(at: db)

    let records = try MaccyImporter(source: .maccy).importRecords(from: db)
    let rich = try XCTUnwrap(records.first { $0.sourceRecordID == "2" })

    XCTAssertEqual(rich.primaryType, .richText)
    XCTAssertEqual(rich.plainTextPreview, "Rich plain")
    XCTAssertEqual(rich.title, "Rich title")
  }

  private func makeMaccyFixture(at url: URL) throws {
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
      CREATE TABLE ZHISTORYITEM (Z_PK INTEGER PRIMARY KEY, ZFIRSTCOPIEDAT REAL, ZLASTCOPIEDAT REAL, ZNUMBEROFCOPIES INTEGER, ZAPPLICATION TEXT, ZPIN TEXT, ZTITLE TEXT);
      CREATE TABLE ZHISTORYITEMCONTENT (Z_PK INTEGER PRIMARY KEY, ZITEM INTEGER, ZTYPE TEXT, ZVALUE BLOB);
      INSERT INTO ZHISTORYITEM VALUES (1, 10, 20, 4, 'Safari', 'pin', 'Ignored title');
      INSERT INTO ZHISTORYITEMCONTENT VALUES (1, 1, 'public.utf8-plain-text', CAST('https://example.com' AS BLOB));
      INSERT INTO ZHISTORYITEMCONTENT VALUES (2, 1, 'org.nspasteboard.source', CAST('com.apple.Safari' AS BLOB));
      INSERT INTO ZHISTORYITEMCONTENT VALUES (3, 1, 'com.apple.is-remote-clipboard', X'01');
      INSERT INTO ZHISTORYITEM VALUES (2, 30, 40, 1, 'TextEdit', NULL, 'Rich title');
      INSERT INTO ZHISTORYITEMCONTENT VALUES (4, 2, 'public.utf8-plain-text', CAST('Rich plain' AS BLOB));
      INSERT INTO ZHISTORYITEMCONTENT VALUES (5, 2, 'public.rtf', X'7B5C727466315C616E736920526963687D');
      """
    XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
  }
}
```

- [ ] **Step 2: Run Maccy tests and verify failure**

Run:

```bash
swift test --filter MaccyImporterTests
```

Expected:

```text
error: cannot find 'MaccyImporter' in scope
```

- [ ] **Step 3: Implement Maccy importer**

Create `Sources/ClipboardCore/Import/MaccyImporter.swift`:

```swift
import Foundation
import SQLite3

public struct MaccyImporter: Sendable {
  private let source: ImportSourceKind

  public init(source: ImportSourceKind) {
    self.source = source
  }

  public func importRecords(from databaseURL: URL) throws -> [ImportedRecord] {
    let db = try ExternalSQLiteDatabase(path: databaseURL.path)
    var contentsByItem: [Int: [(type: String, value: Data)]] = [:]
    try db.rows("SELECT ZITEM, ZTYPE, ZVALUE FROM ZHISTORYITEMCONTENT ORDER BY Z_PK") { stmt in
      let item = stmt.columnInt(0)
      guard let type = stmt.columnText(1) else { return }
      let value = stmt.columnData(2) ?? Data()
      contentsByItem[item, default: []].append((type, value))
    }

    var records: [ImportedRecord] = []
    try db.rows("""
      SELECT Z_PK, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT, ZNUMBEROFCOPIES, ZAPPLICATION, ZPIN, ZTITLE
      FROM ZHISTORYITEM
      ORDER BY ZLASTCOPIEDAT DESC
      """) { stmt in
      let id = stmt.columnInt(0)
      let contents = contentsByItem[id] ?? []
      guard let payload = payload(from: contents) else { return }
      let text = plainText(from: contents)
      let pasteboardTypes = Set(contents.map(\.type))
      let sourceBundle = sourceBundleID(from: contents)
      let primary = primaryType(payload: payload, text: text)
      let title = normalizedTitle(stmt.columnText(6), fallback: text, primary: primary)
      let universal = pasteboardTypes.contains("com.apple.is-remote-clipboard")

      records.append(ImportedRecord(
        source: source,
        sourceRecordID: "\(id)",
        payload: payload,
        primaryType: primary,
        pasteboardTypes: pasteboardTypes,
        title: title,
        plainTextPreview: text,
        sourceAppBundleId: sourceBundle,
        sourceAppName: stmt.columnText(4),
        createdAt: Date(timeIntervalSince1970: stmt.columnDouble(1)),
        lastCopiedAt: Date(timeIntervalSince1970: stmt.columnDouble(2)),
        copyCount: max(1, stmt.columnInt(3)),
        isPinned: !(stmt.columnText(5) ?? "").isEmpty,
        isFavorite: false,
        groupNames: ["Maccy Import"],
        sourceDeviceHint: universal ? .universalClipboard : .imported,
        externalContentHash: nil,
        warnings: unsupportedWarnings(from: contents)
      ))
    }
    return records
  }

  private func payload(from contents: [(type: String, value: Data)]) -> ClipboardPayload? {
    if let image = firstData(["public.png", "public.jpeg", "public.tiff", "public.heic"], in: contents) {
      return .image(data: image.value, uti: image.type)
    }
    if let rtf = firstData(["public.rtf"], in: contents) {
      return .richText(plainText: plainText(from: contents) ?? "", rtfData: rtf.value)
    }
    let urls = fileURLs(from: contents)
    if !urls.isEmpty {
      return .fileURLs(urls)
    }
    if let text = plainText(from: contents) {
      return .text(text)
    }
    return nil
  }

  private func primaryType(payload: ClipboardPayload, text: String?) -> ClipboardContentType {
    switch payload {
    case .image: return .image
    case .richText: return .richText
    case .fileURLs: return .file
    case .text(let value): return isHTTPURLText(value) ? .link : .text
    }
  }

  private func plainText(from contents: [(type: String, value: Data)]) -> String? {
    firstData(["public.utf8-plain-text", "NSStringPboardType"], in: contents)
      .flatMap { String(data: $0.value, encoding: .utf8) }
  }

  private func sourceBundleID(from contents: [(type: String, value: Data)]) -> String? {
    firstData(["org.nspasteboard.source"], in: contents)
      .flatMap { String(data: $0.value, encoding: .utf8) }
  }

  private func fileURLs(from contents: [(type: String, value: Data)]) -> [URL] {
    contents
      .filter { $0.type == "public.file-url" || $0.type == "NSURLPboardType" }
      .compactMap { String(data: $0.value, encoding: .utf8) }
      .compactMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
  }

  private func firstData(_ types: [String], in contents: [(type: String, value: Data)]) -> (type: String, value: Data)? {
    for type in types {
      if let match = contents.first(where: { $0.type == type }) {
        return match
      }
    }
    return nil
  }

  private func normalizedTitle(_ title: String?, fallback: String?, primary: ClipboardContentType) -> String {
    let text = title?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let text, !text.isEmpty { return String(text.prefix(120)) }
    if let fallback, !fallback.isEmpty { return String(fallback.prefix(120)) }
    return primary == .image ? "Image" : "Text"
  }

  private func isHTTPURLText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
          let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          components.host != nil else {
      return false
    }
    return true
  }

  private func unsupportedWarnings(from contents: [(type: String, value: Data)]) -> [String] {
    let supported = Set([
      "public.utf8-plain-text", "NSStringPboardType", "public.rtf",
      "public.png", "public.jpeg", "public.tiff", "public.heic",
      "public.file-url", "NSURLPboardType",
      "org.nspasteboard.source", "com.apple.is-remote-clipboard"
    ])
    return contents.map(\.type).filter { !supported.contains($0) }.map { "Unsupported Maccy pasteboard type: \($0)" }
  }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter MaccyImporterTests
```

Expected:

```text
Test Suite 'MaccyImporterTests' passed
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/ClipboardCore/Import/MaccyImporter.swift Tests/ClipboardCoreTests/MaccyImporterTests.swift
git commit -m "feat: import maccy records"
```

---

### Task 5: Clipaste Importer

**Files:**
- Create: `Sources/ClipboardCore/Import/ClipasteImporter.swift`
- Test: `Tests/ClipboardCoreTests/ClipasteImporterTests.swift`

- [ ] **Step 1: Write failing Clipaste fixture tests**

Create `Tests/ClipboardCoreTests/ClipasteImporterTests.swift`:

```swift
import SQLite3
import XCTest
@testable import ClipboardCore

final class ClipasteImporterTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-clipaste-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testParsesTextLinkGroupsSourceAppAndPin() throws {
    let db = tempDir.appendingPathComponent("clipboard-cloud.store")
    try makeClipasteFixture(at: db)

    let records = try ClipasteImporter(source: .clipasteCloud).importRecords(from: db)

    XCTAssertEqual(records.count, 3)
    let link = try XCTUnwrap(records.first { $0.sourceRecordID == "link-id" })
    XCTAssertEqual(link.payload, .text("https://example.com"))
    XCTAssertEqual(link.primaryType, .link)
    XCTAssertEqual(link.groupNames, ["Work"])
    XCTAssertEqual(link.sourceAppBundleId, "com.apple.Safari")
    XCTAssertEqual(link.sourceAppName, "Safari")
    XCTAssertEqual(link.isPinned, true)
    XCTAssertEqual(link.externalContentHash, "external-link")
  }

  func testCodeMapsToTextWithWarningAndUngroupedDefault() throws {
    let db = tempDir.appendingPathComponent("clipboard-cloud.store")
    try makeClipasteFixture(at: db)

    let records = try ClipasteImporter(source: .clipasteCloud).importRecords(from: db)
    let code = try XCTUnwrap(records.first { $0.sourceRecordID == "code-id" })

    XCTAssertEqual(code.primaryType, .text)
    XCTAssertEqual(code.groupNames, ["Clipaste Import"])
    XCTAssertTrue(code.warnings.contains("Clipaste code imported as text"))
  }

  private func makeClipasteFixture(at url: URL) throws {
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
      CREATE TABLE ZCLIPBOARDGROUPMODEL (Z_PK INTEGER PRIMARY KEY, ZID TEXT, ZNAME TEXT, ZSYSTEMICONNAME TEXT, ZSORTORDER REAL, ZCREATEDAT REAL);
      CREATE TABLE ZCLIPBOARDRECORD (
        Z_PK INTEGER PRIMARY KEY, ZID TEXT, ZTIMESTAMP REAL, ZAPPBUNDLEID TEXT, ZAPPLOCALIZEDNAME TEXT,
        ZCONTENTHASH TEXT, ZCUSTOMTITLE TEXT, ZGROUPID TEXT, ZGROUPIDSRAW TEXT, ZIMAGEUTTYPE TEXT,
        ZLINKTITLE TEXT, ZPLAINTEXT TEXT, ZTYPERAWVALUE TEXT, ZISPINNED INTEGER,
        ZIMAGEDATA BLOB, ZRTFDATA BLOB, ZRICHTEXTARCHIVEDATA BLOB, ZPREVIEWIMAGEDATA BLOB
      );
      INSERT INTO ZCLIPBOARDGROUPMODEL (ZID, ZNAME) VALUES ('g1', 'Work');
      INSERT INTO ZCLIPBOARDRECORD (ZID, ZTIMESTAMP, ZAPPBUNDLEID, ZAPPLOCALIZEDNAME, ZCONTENTHASH, ZGROUPID, ZPLAINTEXT, ZTYPERAWVALUE, ZISPINNED)
        VALUES ('link-id', 100, 'com.apple.Safari', 'Safari', 'external-link', 'g1', 'https://example.com', 'link', 1);
      INSERT INTO ZCLIPBOARDRECORD (ZID, ZTIMESTAMP, ZCONTENTHASH, ZPLAINTEXT, ZTYPERAWVALUE, ZISPINNED)
        VALUES ('code-id', 101, 'external-code', 'let x = 1', 'code', 0);
      INSERT INTO ZCLIPBOARDRECORD (ZID, ZTIMESTAMP, ZCONTENTHASH, ZPLAINTEXT, ZTYPERAWVALUE, ZISPINNED, ZRTFDATA)
        VALUES ('rtf-id', 102, 'external-rtf', 'Rich', 'richText', 0, X'7B5C727466315C616E736920526963687D');
      """
    XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
  }
}
```

- [ ] **Step 2: Run Clipaste tests and verify failure**

Run:

```bash
swift test --filter ClipasteImporterTests
```

Expected:

```text
error: cannot find 'ClipasteImporter' in scope
```

- [ ] **Step 3: Implement Clipaste importer**

Create `Sources/ClipboardCore/Import/ClipasteImporter.swift`:

```swift
import Foundation
import SQLite3

public struct ClipasteImporter: Sendable {
  private let source: ImportSourceKind

  public init(source: ImportSourceKind) {
    self.source = source
  }

  public func importRecords(from databaseURL: URL) throws -> [ImportedRecord] {
    let db = try ExternalSQLiteDatabase(path: databaseURL.path)
    let groups = try loadGroups(db)
    var records: [ImportedRecord] = []
    try db.rows("""
      SELECT Z_PK, ZID, ZTIMESTAMP, ZAPPBUNDLEID, ZAPPLOCALIZEDNAME, ZCONTENTHASH,
             ZCUSTOMTITLE, ZGROUPID, ZGROUPIDSRAW, ZIMAGEUTTYPE, ZLINKTITLE,
             ZPLAINTEXT, ZTYPERAWVALUE, ZISPINNED, ZIMAGEDATA, ZRTFDATA
      FROM ZCLIPBOARDRECORD
      ORDER BY ZTIMESTAMP DESC
      """) { stmt in
      guard let imported = makeRecord(stmt: stmt, groups: groups) else { return }
      records.append(imported)
    }
    return records
  }

  private func loadGroups(_ db: ExternalSQLiteDatabase) throws -> [String: String] {
    guard try db.hasTable("ZCLIPBOARDGROUPMODEL") else { return [:] }
    var groups: [String: String] = [:]
    try db.rows("SELECT ZID, ZNAME FROM ZCLIPBOARDGROUPMODEL") { stmt in
      if let id = stmt.columnText(0), let name = stmt.columnText(1), !name.isEmpty {
        groups[id] = name
      }
    }
    return groups
  }

  private func makeRecord(stmt: Statement, groups: [String: String]) -> ImportedRecord? {
    let pk = stmt.columnInt(0)
    let sourceID = stmt.columnText(1) ?? "\(pk)"
    let timestamp = Date(timeIntervalSince1970: stmt.columnDouble(2))
    let bundleID = stmt.columnText(3)
    let appName = stmt.columnText(4)
    let externalHash = stmt.columnText(5)
    let customTitle = stmt.columnText(6)
    let groupID = stmt.columnText(7)
    let groupIDsRaw = stmt.columnText(8)
    let imageUTI = stmt.columnText(9) ?? "public.data"
    let linkTitle = stmt.columnText(10)
    let plainText = stmt.columnText(11)
    let type = stmt.columnText(12) ?? "text"
    let isPinned = stmt.columnBool(13)
    let imageData = stmt.columnData(14)
    let rtfData = stmt.columnData(15)

    var warnings: [String] = []
    let payload: ClipboardPayload
    let primary: ClipboardContentType

    switch type {
    case "image":
      guard let imageData else { return nil }
      payload = .image(data: imageData, uti: imageUTI)
      primary = .image
    case "richText":
      guard let rtfData else { return nil }
      payload = .richText(plainText: plainText ?? "", rtfData: rtfData)
      primary = .richText
    case "fileURL":
      let urls = (plainText ?? "")
        .split(whereSeparator: \.isNewline)
        .compactMap { URL(string: String($0)) }
      guard !urls.isEmpty else { return nil }
      payload = .fileURLs(urls)
      primary = .file
    case "link":
      guard let plainText else { return nil }
      payload = .text(plainText)
      primary = .link
    case "code":
      guard let plainText else { return nil }
      payload = .text(plainText)
      primary = .text
      warnings.append("Clipaste code imported as text")
    default:
      guard let plainText else { return nil }
      payload = .text(plainText)
      primary = isHTTPURLText(plainText) ? .link : .text
    }

    let names = groupNames(groupID: groupID, raw: groupIDsRaw, groups: groups)
    return ImportedRecord(
      source: source,
      sourceRecordID: sourceID,
      payload: payload,
      primaryType: primary,
      pasteboardTypes: pasteboardTypes(type: type, imageUTI: imageUTI),
      title: firstNonEmpty([customTitle, linkTitle, plainText]) ?? defaultTitle(primary),
      plainTextPreview: plainText,
      sourceAppBundleId: bundleID,
      sourceAppName: appName,
      createdAt: timestamp,
      lastCopiedAt: timestamp,
      copyCount: 1,
      isPinned: isPinned,
      isFavorite: false,
      groupNames: names.isEmpty ? ["Clipaste Import"] : names,
      sourceDeviceHint: .imported,
      externalContentHash: externalHash,
      warnings: warnings
    )
  }

  private func groupNames(groupID: String?, raw: String?, groups: [String: String]) -> [String] {
    var ids: [String] = []
    if let groupID, !groupID.isEmpty { ids.append(groupID) }
    if let raw {
      ids.append(contentsOf: raw
        .components(separatedBy: CharacterSet(charactersIn: ",;[]\" "))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty })
    }
    var result: [String] = []
    for id in ids {
      if let name = groups[id], !result.contains(name) {
        result.append(name)
      }
    }
    return result
  }

  private func pasteboardTypes(type: String, imageUTI: String) -> Set<String> {
    switch type {
    case "image": return [imageUTI]
    case "richText": return ["public.rtf", "public.utf8-plain-text"]
    case "fileURL": return ["public.file-url"]
    default: return ["public.utf8-plain-text"]
    }
  }

  private func firstNonEmpty(_ values: [String?]) -> String? {
    values.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }.map { String($0.prefix(120)) }
  }

  private func defaultTitle(_ type: ClipboardContentType) -> String {
    switch type {
    case .text: return "Text"
    case .richText: return "Rich Text"
    case .link: return "Link"
    case .image: return "Image"
    case .file: return "Files"
    }
  }

  private func isHTTPURLText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
          let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          components.host != nil else {
      return false
    }
    return true
  }
}
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
swift test --filter ClipasteImporterTests
```

Expected:

```text
Test Suite 'ClipasteImporterTests' passed
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/ClipboardCore/Import/ClipasteImporter.swift Tests/ClipboardCoreTests/ClipasteImporterTests.swift
git commit -m "feat: import clipaste records"
```

---

### Task 6: Import-Aware Storage Writes

**Files:**
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`
- Test: `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`

- [ ] **Step 1: Add failing tests for full-record import replacement**

Append to `SQLiteHistoryStoreTests`:

```swift
  func testImportRecordReplacesFullRecordWithoutIncrementingCopyCount() async throws {
    let store = try makeStore()
    _ = try await store.upsert(makeRecord(hash: "same", title: "old"))
    var imported = makeRecord(hash: "same", title: "new", isPinned: true)
    imported.copyCount = 7
    imported.groupIds = ["clipaste-import"]
    imported.lastCopiedAt = Date(timeIntervalSince1970: 999)

    let result = try await store.importRecord(imported)

    XCTAssertEqual(result.title, "new")
    XCTAssertEqual(result.copyCount, 7)
    XCTAssertEqual(result.groupIds, ["clipaste-import"])
    XCTAssertEqual(result.isPinned, true)
    let all = try await store.fetchAll()
    XCTAssertEqual(all.count, 1)
    XCTAssertEqual(all[0].title, "new")
  }

  func testRecordForContentHashFindsExistingRecord() async throws {
    let store = try makeStore()
    let inserted = try await store.upsert(makeRecord(hash: "lookup", title: "lookup"))

    let found = try await store.record(forContentHash: "lookup")

    XCTAssertEqual(found, inserted)
  }
```

- [ ] **Step 2: Run storage tests and verify failure**

Run:

```bash
swift test --filter SQLiteHistoryStoreTests/testImportRecordReplacesFullRecordWithoutIncrementingCopyCount
```

Expected:

```text
value of type 'SQLiteHistoryStore' has no member 'importRecord'
```

- [ ] **Step 3: Add import-write protocol and in-memory conformance**

Modify `Sources/ClipboardCore/Storage/HistoryStore.swift`:

```swift
public protocol ImportWritableHistoryStore: HistoryStore {
  func record(forContentHash hash: String) async throws -> ClipboardRecord?
  func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord
}
```

Add to `InMemoryHistoryStore`:

```swift
  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    recordsByHash[hash]
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    recordsByHash[record.contentHash] = record
    return record
  }
```

Change declaration:

```swift
public actor InMemoryHistoryStore: ImportWritableHistoryStore {
```

- [ ] **Step 4: Add SQLite import replacement**

Modify `SQLiteHistoryStore` declaration:

```swift
public actor SQLiteHistoryStore: ImportWritableHistoryStore, RetentionPolicyUpdating {
```

Add public methods:

```swift
  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    indexByHash[hash]
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    try connection.exec("BEGIN IMMEDIATE")
    inExplicitTransaction = true
    defer { inExplicitTransaction = false }
    do {
      try writeRecordForImport(record)
      indexByHash[record.contentHash] = record
      try enforceRetention()
      try connection.exec("COMMIT")
      return record
    } catch {
      try? connection.exec("ROLLBACK")
      throw error
    }
  }
```

Add private writer:

```swift
  private func writeRecordForImport(_ r: ClipboardRecord) throws {
    let sql = """
      INSERT INTO records (
        id, content_hash, primary_type, title, plain_preview,
        source_bundle, source_app, source_device,
        created_at, last_copied_at, copy_count,
        is_pinned, is_favorite, group_ids_json, retention_exempt,
        metadata_json, pasteboard_types_json, payload_ref
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(content_hash) DO UPDATE SET
        id = excluded.id,
        primary_type = excluded.primary_type,
        title = excluded.title,
        plain_preview = excluded.plain_preview,
        source_bundle = excluded.source_bundle,
        source_app = excluded.source_app,
        source_device = excluded.source_device,
        created_at = excluded.created_at,
        last_copied_at = excluded.last_copied_at,
        copy_count = excluded.copy_count,
        is_pinned = excluded.is_pinned,
        is_favorite = excluded.is_favorite,
        group_ids_json = excluded.group_ids_json,
        retention_exempt = excluded.retention_exempt,
        metadata_json = excluded.metadata_json,
        pasteboard_types_json = excluded.pasteboard_types_json
    """
    let stmt = try connection.prepare(sql)
    defer { stmt.finalize() }
    stmt.bindText(1, r.id.uuidString)
    stmt.bindText(2, r.contentHash)
    stmt.bindText(3, r.primaryType.rawValue)
    stmt.bindText(4, r.title)
    stmt.bindText(5, r.plainTextPreview)
    stmt.bindText(6, r.sourceAppBundleId)
    stmt.bindText(7, r.sourceAppName)
    stmt.bindText(8, r.sourceDeviceHint.rawValue)
    stmt.bindDouble(9, r.createdAt.timeIntervalSince1970)
    stmt.bindDouble(10, r.lastCopiedAt.timeIntervalSince1970)
    stmt.bindInt(11, r.copyCount)
    stmt.bindBool(12, r.isPinned)
    stmt.bindBool(13, r.isFavorite)
    stmt.bindText(14, try Self.encodeJSON(r.groupIds))
    stmt.bindBool(15, r.retentionExempt)
    stmt.bindText(16, try Self.encodeJSONOptional(r.metadata))
    stmt.bindText(17, try Self.encodeJSON(Array(r.pasteboardTypes)))
    stmt.bindText(18, nil)
    _ = try stmt.step()
  }
```

- [ ] **Step 5: Forward through decorators**

Make `SelfHealingHistoryStore` conform to `ImportWritableHistoryStore` and add:

```swift
  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    guard let importing = underlying as? any ImportWritableHistoryStore else { return nil }
    return try await importing.record(forContentHash: hash)
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    guard let importing = underlying as? any ImportWritableHistoryStore else {
      return try await upsert(record)
    }
    var attempt = 0
    while true {
      do {
        return try await importing.importRecord(record)
      } catch StorageError.full {
        guard attempt < maxRounds else { throw StorageError.full }
        let removed = try await underlying.evictOldest(percent: evictPercent)
        if removed == 0 {
          throw StorageError.fullAndCannotEvict
        }
        attempt += 1
      }
    }
  }
```

Make `PayloadCleaningHistoryStore` conform to `ImportWritableHistoryStore` and add:

```swift
  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    guard let importing = underlying as? any ImportWritableHistoryStore else { return nil }
    return try await importing.record(forContentHash: hash)
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    let before = try await underlying.fetchAll()
    let result: ClipboardRecord
    if let importing = underlying as? any ImportWritableHistoryStore {
      result = try await importing.importRecord(record)
    } else {
      result = try await underlying.upsert(record)
    }
    try await deletePayloadsForRecordsRemoved(from: before)
    return result
  }
```

- [ ] **Step 6: Run storage tests**

Run:

```bash
swift test --filter SQLiteHistoryStoreTests
```

Expected:

```text
Test Suite 'SQLiteHistoryStoreTests' passed
```

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/ClipboardCore/Storage/HistoryStore.swift Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift
git commit -m "feat: add import-aware history writes"
```

---

### Task 7: Import Service, Deduplication, Batch Commit, Reports

**Files:**
- Create: `Sources/ClipboardCore/Import/ImportService.swift`
- Modify: `Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift`
- Test: `Tests/ClipboardCoreTests/ImportServiceTests.swift`

- [ ] **Step 1: Write failing ImportService tests**

Create `Tests/ClipboardCoreTests/ImportServiceTests.swift`:

```swift
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

  func testNewestImportReplacesOlderExistingAndMergesMetadata() async throws {
    let store = InMemoryHistoryStore()
    let payloads = InMemoryPayloadStore()
    let builder = ImportRecordBuilder()
    let older = try builder.buildRecord(from: .fixture(text: "same", lastCopiedAt: 10, copyCount: 2, groupNames: ["Current"]), groupIDs: ["current"])
    _ = try await store.importRecord(older)
    try await payloads.save(.text("same"), for: older.id)

    let service = ImportService(historyStore: store, payloadStore: payloads, reportsDirectory: tempDir)
    let report = try await service.importRecords([.fixture(text: "same", lastCopiedAt: 20, copyCount: 5, groupNames: ["Clipaste Import"], pinned: true)], batchSize: 10)

    XCTAssertEqual(report.status, .completed)
    XCTAssertEqual(report.replacedByNewest, 1)
    let records = try await store.fetchAll()
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].lastCopiedAt, Date(timeIntervalSince1970: 20))
    XCTAssertEqual(records[0].copyCount, 7)
    XCTAssertEqual(Set(records[0].groupIds), ["current", "clipaste-import"])
    XCTAssertTrue(records[0].isPinned)
  }

  func testCancellationKeepsCommittedBatchesAndWritesCancelledReport() async throws {
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
    XCTAssertEqual(try await store.count(), 1)
    let files = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
    XCTAssertTrue(files.contains(where: { $0.hasSuffix(".json") }))
  }
}

private extension ImportedRecord {
  static func fixture(
    text: String,
    lastCopiedAt: TimeInterval,
    copyCount: Int = 1,
    groupNames: [String] = ["Clipaste Import"],
    pinned: Bool = false
  ) -> ImportedRecord {
    ImportedRecord(
      source: .clipasteCloud,
      sourceRecordID: text,
      payload: .text(text),
      primaryType: text.hasPrefix("http") ? .link : .text,
      pasteboardTypes: ["public.utf8-plain-text"],
      title: text,
      plainTextPreview: text,
      sourceAppBundleId: nil,
      sourceAppName: nil,
      createdAt: Date(timeIntervalSince1970: lastCopiedAt),
      lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
      copyCount: copyCount,
      isPinned: pinned,
      isFavorite: false,
      groupNames: groupNames,
      sourceDeviceHint: .imported,
      externalContentHash: nil,
      warnings: []
    )
  }
}
```

- [ ] **Step 2: Run service tests and verify failure**

Run:

```bash
swift test --filter ImportServiceTests
```

Expected:

```text
error: cannot find 'ImportService' in scope
```

- [ ] **Step 3: Add reports directory path**

Modify `ApplicationSupportPaths`:

```swift
  public let importReportsDirectory: URL
```

In initializer:

```swift
    self.importReportsDirectory = base.appendingPathComponent("imports/reports", isDirectory: true)
```

In `prepare()`:

```swift
    if !fm.fileExists(atPath: importReportsDirectory.path) {
      try fm.createDirectory(at: importReportsDirectory, withIntermediateDirectories: true)
    }
```

- [ ] **Step 4: Implement ImportService**

Create `Sources/ClipboardCore/Import/ImportService.swift`:

```swift
import Foundation

public struct ImportProgress: Equatable, Sendable {
  public let scanned: Int
  public let committedBatchCount: Int
  public let lastProcessedSourceRecordID: String?
}

public actor ImportService {
  private let historyStore: any ImportWritableHistoryStore
  private let payloadStore: any ClipboardPayloadStore
  private let reportsDirectory: URL
  private let builder: ImportRecordBuilder
  private let fileManager: FileManager

  public init(
    historyStore: any ImportWritableHistoryStore,
    payloadStore: any ClipboardPayloadStore,
    reportsDirectory: URL,
    builder: ImportRecordBuilder = ImportRecordBuilder(),
    fileManager: FileManager = .default
  ) {
    self.historyStore = historyStore
    self.payloadStore = payloadStore
    self.reportsDirectory = reportsDirectory
    self.builder = builder
    self.fileManager = fileManager
  }

  public func importRecords(
    _ imported: [ImportedRecord],
    batchSize: Int = 100,
    shouldCancel: @Sendable (ImportProgress) -> Bool = { _ in false }
  ) async throws -> ImportReport {
    let start = Date()
    var report = ImportReport(status: .completed, sources: Array(Set(imported.map { $0.source.rawValue })).sorted())
    var batch: [ImportedRecord] = []

    for record in imported {
      report.scanned += 1
      report.lastProcessedSourceRecordID = record.sourceRecordID
      batch.append(record)
      if batch.count >= max(1, batchSize) {
        if shouldCancel(ImportProgress(scanned: report.scanned, committedBatchCount: report.committedBatchCount, lastProcessedSourceRecordID: report.lastProcessedSourceRecordID)) {
          report.status = .cancelled
          report.skipped += batch.count
          report.duration = Date().timeIntervalSince(start)
          try writeReport(report)
          return report
        }
        try await commit(batch, report: &report)
        batch.removeAll()
      }
    }

    if !batch.isEmpty {
      if shouldCancel(ImportProgress(scanned: report.scanned, committedBatchCount: report.committedBatchCount, lastProcessedSourceRecordID: report.lastProcessedSourceRecordID)) {
        report.status = .cancelled
        report.skipped += batch.count
      } else {
        try await commit(batch, report: &report)
      }
    }

    report.duration = Date().timeIntervalSince(start)
    try writeReport(report)
    return report
  }

  private func commit(_ records: [ImportedRecord], report: inout ImportReport) async throws {
    for imported in records {
      do {
        let groupIDs = imported.groupNames.map(normalizedGroupID)
        var candidate = try builder.buildRecord(from: imported, groupIDs: groupIDs)
        if var existing = try await historyStore.record(forContentHash: candidate.contentHash) {
          let newestIsImport = candidate.lastCopiedAt >= existing.lastCopiedAt
          if newestIsImport {
            let mergedPasteboardTypes = existing.pasteboardTypes.union(candidate.pasteboardTypes)
            let replacement = ClipboardRecord(
              id: existing.id,
              contentHash: candidate.contentHash,
              primaryType: candidate.primaryType,
              title: candidate.title,
              plainTextPreview: candidate.plainTextPreview,
              sourceAppBundleId: candidate.sourceAppBundleId,
              sourceAppName: candidate.sourceAppName,
              sourceDeviceHint: candidate.sourceDeviceHint,
              createdAt: min(existing.createdAt, candidate.createdAt),
              lastCopiedAt: candidate.lastCopiedAt,
              copyCount: boundedCopyCount(existing.copyCount + candidate.copyCount),
              isPinned: existing.isPinned || candidate.isPinned,
              isFavorite: existing.isFavorite || candidate.isFavorite,
              groupIds: union(existing.groupIds, candidate.groupIds),
              retentionExempt: existing.retentionExempt || candidate.retentionExempt || existing.isPinned || candidate.isPinned || existing.isFavorite || candidate.isFavorite,
              metadata: candidate.metadata ?? existing.metadata,
              pasteboardTypes: mergedPasteboardTypes
            )
            _ = try await historyStore.importRecord(replacement)
            try await payloadStore.save(imported.payload, for: replacement.id)
            report.replacedByNewest += 1
          } else {
            existing.copyCount = boundedCopyCount(existing.copyCount + candidate.copyCount)
            existing.groupIds = union(existing.groupIds, candidate.groupIds)
            existing.isPinned = existing.isPinned || candidate.isPinned
            existing.isFavorite = existing.isFavorite || candidate.isFavorite
            existing.retentionExempt = existing.isPinned || existing.isFavorite || existing.retentionExempt
            existing.pasteboardTypes.formUnion(candidate.pasteboardTypes)
            _ = try await historyStore.importRecord(existing)
            report.merged += 1
          }
        } else {
          _ = try await historyStore.importRecord(candidate)
          try await payloadStore.save(imported.payload, for: candidate.id)
          report.imported += 1
        }
        report.warnings.append(contentsOf: imported.warnings)
        report.createdGroupIDs.append(contentsOf: groupIDs.filter { !report.createdGroupIDs.contains($0) })
      } catch {
        report.failed += 1
        report.failures.append(ImportFailure(
          source: imported.source,
          sourceRecordID: imported.sourceRecordID,
          titleOrPreview: imported.title,
          reason: String(describing: error)
        ))
      }
    }
    report.committedBatchCount += 1
  }

  private func normalizedGroupID(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let scalars = trimmed.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
    let slug = String(scalars).split(separator: "-").joined(separator: "-")
    return slug.isEmpty ? "imported" : slug
  }

  private func union(_ first: [String], _ second: [String]) -> [String] {
    var result = first
    for value in second where !result.contains(value) {
      result.append(value)
    }
    return result
  }

  private func boundedCopyCount(_ value: Int) -> Int {
    min(max(1, value), 1_000_000)
  }

  private func writeReport(_ report: ImportReport) throws {
    if !fileManager.fileExists(atPath: reportsDirectory.path) {
      try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
    }
    let formatter = ISO8601DateFormatter()
    let stamp = formatter.string(from: report.createdAt).replacingOccurrences(of: ":", with: "")
    let url = reportsDirectory.appendingPathComponent("\(stamp)-import.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(report).write(to: url, options: .atomic)
  }
}
```

- [ ] **Step 5: Run service tests**

Run:

```bash
swift test --filter ImportServiceTests
```

Expected:

```text
Test Suite 'ImportServiceTests' passed
```

- [ ] **Step 6: Commit**

Run:

```bash
git add Sources/ClipboardCore/Import/ImportService.swift Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift Tests/ClipboardCoreTests/ImportServiceTests.swift
git commit -m "feat: import records with newest merge"
```

---

### Task 8: Settings Import Page

**Files:**
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Modify: `Sources/ClipboardApp/Settings/SettingsWindow.swift`
- Create: `Sources/ClipboardApp/Settings/ImportSettingsView.swift`
- Test: `Tests/ClipboardAppTests/ImportSettingsViewTests.swift`

- [ ] **Step 1: Add a focused Settings page test**

Create `Tests/ClipboardAppTests/ImportSettingsViewTests.swift`:

```swift
import XCTest
@testable import ClipboardApp

final class ImportSettingsViewTests: XCTestCase {
  func testSettingsPageIncludesImport() {
    XCTAssertTrue(SettingsPage.allCases.contains(.importData))
    XCTAssertEqual(SettingsPage.importData.systemImage, "square.and.arrow.down")
  }
}
```

- [ ] **Step 2: Run app test and verify failure**

Run:

```bash
swift test --filter ImportSettingsViewTests
```

Expected:

```text
type 'SettingsPage' has no member 'importData'
```

- [ ] **Step 3: Expose ImportService from AppServices**

Modify `AppServices`:

```swift
  let importService: ImportService?
  let importReportsDirectory: URL?
```

In `init()`, keep `ApplicationSupportPaths` from `makeStorage` by changing the helper return tuple to include paths:

```swift
  private static func makeStorage(bundleId: String) -> (any HistoryStore, any ClipboardPayloadStore, StorageHealth, ApplicationSupportPaths?)
```

When SQLite-backed storage succeeds, return `(cleaning, payloads, .ok, paths)`. When falling back to in-memory, return `(InMemoryHistoryStore(), InMemoryPayloadStore(), .disabled(reason: reason), nil)`.

After assigning `store` and `payloadStore`:

```swift
    self.importReportsDirectory = paths?.importReportsDirectory
    if let importingStore = storeImpl as? any ImportWritableHistoryStore,
       let reports = paths?.importReportsDirectory {
      self.importService = ImportService(
        historyStore: importingStore,
        payloadStore: payloadImpl,
        reportsDirectory: reports
      )
    } else {
      self.importService = nil
    }
```

- [ ] **Step 4: Add Settings page case**

Modify `SettingsWindow.swift`:

```swift
    case importData = "导入"
```

Add icon:

```swift
        case .importData: return "square.and.arrow.down"
```

Add detail switch:

```swift
            case .importData:
                ImportSettingsView(services: services)
```

- [ ] **Step 5: Add Import Settings UI**

Create `Sources/ClipboardApp/Settings/ImportSettingsView.swift`:

```swift
import ClipboardCore
import SwiftUI
import AppKit

struct ImportSettingsView: View {
  @ObservedObject var services: AppServices
  @State private var candidates: [ImportSourceCandidate] = []
  @State private var selectedIDs: Set<String> = []
  @State private var latestReport: ImportReport?
  @State private var statusText = "尚未扫描"
  @State private var isRunning = false

  private let discovery = ImportSourceDiscovery()
  private let snapshotService = ImportSnapshotService()

  var body: some View {
    Form {
      Section("自动来源") {
        Button("扫描 Maccy 和 Clipaste") {
          scan()
        }
        ForEach(candidates) { candidate in
          Toggle(isOn: binding(for: candidate.id)) {
            VStack(alignment: .leading, spacing: 4) {
              Text(candidate.displayName)
              Text(candidate.databaseURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
              Text("\(candidate.schemaStatus) · \(candidate.recordCount ?? 0) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Section("手动数据库") {
        Button("选择数据库文件") {
          chooseManualDatabase()
        }
      }

      Section("导入") {
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack {
          Button(isRunning ? "导入中" : "开始导入") {
            startImport()
          }
          .disabled(isRunning || selectedIDs.isEmpty || services.importService == nil)
        }
      }

      if let latestReport {
        Section("最新报告") {
          Text("状态：\(latestReport.status.rawValue)")
          Text("扫描：\(latestReport.scanned)，新增：\(latestReport.imported)，合并：\(latestReport.merged)，最新覆盖：\(latestReport.replacedByNewest)，失败：\(latestReport.failed)")
            .font(.caption)
          Button("复制报告") {
            copyReport(latestReport)
          }
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { scan() }
  }

  private func binding(for id: String) -> Binding<Bool> {
    Binding(
      get: { selectedIDs.contains(id) },
      set: { isOn in
        if isOn { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
      }
    )
  }

  private func scan() {
    candidates = discovery.discoverAutomaticSources()
    selectedIDs = Set(candidates.filter(\.isDefaultSelected).map(\.id))
    statusText = candidates.isEmpty ? "未发现可导入来源" : "发现 \(candidates.count) 个来源"
  }

  private func chooseManualDatabase() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.allowedContentTypes = []
    if panel.runModal() == .OK, let url = panel.url, let candidate = try? discovery.classifyManualDatabase(url) {
      candidates.append(candidate)
      if candidate.schemaKind != .unknown {
        selectedIDs.insert(candidate.id)
      }
    }
  }

  private func startImport() {
    guard let service = services.importService else {
      statusText = "当前存储不可写，无法导入"
      return
    }
    let selected = candidates.filter { selectedIDs.contains($0.id) }
    isRunning = true
    statusText = "正在导入"
    Task {
      do {
        var imported: [ImportedRecord] = []
        for candidate in selected {
          let snapshot = try snapshotService.snapshot(databaseURL: candidate.databaseURL)
          switch candidate.schemaKind {
          case .maccy:
            imported.append(contentsOf: try MaccyImporter(source: candidate.kind).importRecords(from: snapshot.databaseURL))
          case .clipaste:
            imported.append(contentsOf: try ClipasteImporter(source: candidate.kind).importRecords(from: snapshot.databaseURL))
          case .unknown:
            break
          }
        }
        let report = try await service.importRecords(imported)
        await MainActor.run {
          latestReport = report
          statusText = "导入完成"
          isRunning = false
        }
      } catch {
        await MainActor.run {
          statusText = "导入失败：\(error.localizedDescription)"
          isRunning = false
        }
      }
    }
  }

  private func copyReport(_ report: ImportReport) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let text = (try? String(data: encoder.encode(report), encoding: .utf8)) ?? "\(report)"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
```

- [ ] **Step 6: Run app tests**

Run:

```bash
swift test --filter ImportSettingsViewTests
```

Expected:

```text
Test Suite 'ImportSettingsViewTests' passed
```

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/ClipboardApp/AppServices.swift Sources/ClipboardApp/Settings/SettingsWindow.swift Sources/ClipboardApp/Settings/ImportSettingsView.swift Tests/ClipboardAppTests/ImportSettingsViewTests.swift
git commit -m "feat: add import settings page"
```

---

### Task 9: End-To-End Verification And Acceptance Notes

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Run complete test suite**

Run:

```bash
swift test
```

Expected:

```text
Build complete!
Test Suite 'All tests' passed
```

- [ ] **Step 2: Run existing verification script**

Run:

```bash
Scripts/verify.sh
```

Expected:

```text
✅
```

If the script uses different success text, accept exit code `0` and record the final success lines in the task notes.

- [ ] **Step 3: Add manual import acceptance checklist**

Append to `docs/manual-acceptance-checklist.md`:

```markdown

## Maccy and Clipaste Import

- [ ] Settings contains an Import page.
- [ ] Automatic scan finds `/Applications/Maccy.app` data when the source store exists.
- [ ] Automatic scan finds `/Applications/Clipaste.app` cloud/local stores when they exist.
- [ ] Clipaste cloud store is default-selected when valid.
- [ ] Manual file selection accepts a Maccy `Storage.sqlite`.
- [ ] Manual file selection accepts a Clipaste `.store` file.
- [ ] Manual file selection rejects unrelated SQLite files.
- [ ] Maccy import preserves text, link, rich text, image, file URL, source app, pin, copy count, and Universal Clipboard marker when present.
- [ ] Clipaste import preserves text, link, image, rich text, code-as-text, source app, pin, and groups when present.
- [ ] Reimport does not create duplicate history records.
- [ ] Duplicate content keeps the record with newest `lastCopiedAt` and merges copy count, pin/favorite, groups, and pasteboard types.
- [ ] Cancelled import keeps committed batches and writes a cancelled report.
- [ ] Import report JSON is written under Application Support `imports/reports`.
```

- [ ] **Step 4: Build app bundle**

Run:

```bash
Scripts/build-app-bundle.sh
```

Expected:

```text
ClipboardApp.app
```

- [ ] **Step 5: Commit verification docs**

Run:

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: add import acceptance checklist"
```

---

## Self-Review Checklist

- Spec coverage:
  - Automatic source discovery: Task 3 and Task 8.
  - Manual SQLite/SwiftData store selection: Task 3 and Task 8.
  - Snapshot of running source apps with sidecars: Task 2 and Task 8.
  - Maccy high-fidelity `ZHISTORYITEM` + `ZHISTORYITEMCONTENT` parsing: Task 4.
  - Clipaste cloud/local schema parsing and groups: Task 5.
  - Current-app hash dedupe and newest-time replacement: Task 1, Task 6, Task 7.
  - Batch commits, cancellation, and report JSON: Task 7.
  - Settings Import page and latest report display: Task 8.
  - Manual acceptance and full verification: Task 9.
- Placeholder scan:
  - The plan avoids unresolved markers and undefined task references.
  - Every code-writing task names exact files and includes concrete test commands.
- Type consistency:
  - `ImportedRecord`, `ImportSourceKind`, `ImportSourceCandidate`, `ImportReport`, `ImportRecordBuilder`, `ImportSnapshotService`, `ExternalSQLiteDatabase`, `MaccyImporter`, `ClipasteImporter`, and `ImportService` are introduced before downstream use.
  - `ImportWritableHistoryStore` is introduced before `ImportService` depends on it.
  - Settings uses `ImportService?` because persistent storage can fall back to in-memory-disabled startup mode.
