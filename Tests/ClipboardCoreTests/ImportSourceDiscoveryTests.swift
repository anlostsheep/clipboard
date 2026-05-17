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
    let db = tempDir.appendingPathComponent("arbitrary.store")
    try makeMaccySchema(at: db)

    let candidate = try ImportSourceDiscovery(homeDirectory: tempDir).classifyManualDatabase(db)

    XCTAssertEqual(candidate.schemaKind, .maccy)
    XCTAssertEqual(candidate.kind, .manualMaccy)
    XCTAssertEqual(candidate.displayName, "arbitrary.store")
    XCTAssertEqual(candidate.databaseURL, db)
    XCTAssertEqual(candidate.recordCount, 0)
    XCTAssertEqual(candidate.typeDistribution, [:])
    XCTAssertEqual(candidate.schemaStatus, "OK")
    XCTAssertTrue(candidate.isDefaultSelected)
  }

  func testClassifiesManualClipasteBySchema() throws {
    let db = tempDir.appendingPathComponent("Storage.sqlite")
    try makeClipasteSchema(at: db)

    let candidate = try ImportSourceDiscovery(homeDirectory: tempDir).classifyManualDatabase(db)

    XCTAssertEqual(candidate.schemaKind, .clipaste)
    XCTAssertEqual(candidate.kind, .manualClipaste)
    XCTAssertEqual(candidate.displayName, "Storage.sqlite")
    XCTAssertEqual(candidate.databaseURL, db)
    XCTAssertEqual(candidate.recordCount, 0)
    XCTAssertEqual(candidate.typeDistribution, [:])
    XCTAssertEqual(candidate.schemaStatus, "OK")
    XCTAssertTrue(candidate.isDefaultSelected)
  }

  func testRejectsUnknownSQLiteSchema() throws {
    let db = tempDir.appendingPathComponent("unknown.sqlite")
    try createDB(at: db, sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY)")

    let candidate = try ImportSourceDiscovery(homeDirectory: tempDir).classifyManualDatabase(db)

    XCTAssertEqual(candidate.schemaKind, .unknown)
    XCTAssertEqual(candidate.schemaStatus, "Unsupported schema")
    XCTAssertNil(candidate.recordCount)
    XCTAssertEqual(candidate.typeDistribution, [:])
    XCTAssertFalse(candidate.isDefaultSelected)
  }

  func testDiscoversAutomaticSourcesFromInjectedHomeDirectory() throws {
    let maccy = standardMaccyURL()
    let cloud = standardClipasteCloudURL()
    try makeMaccySchema(at: maccy)
    try makeClipasteSchema(at: cloud)

    let candidates = ImportSourceDiscovery(homeDirectory: tempDir).discoverAutomaticSources()

    XCTAssertEqual(candidates.map(\.kind), [.maccy, .clipasteCloud])
    XCTAssertEqual(candidates.map(\.databaseURL), [maccy, cloud])
    XCTAssertEqual(candidates.map(\.schemaKind), [.maccy, .clipaste])
    XCTAssertTrue(candidates.allSatisfy { $0.schemaStatus == "OK" })
  }

  func testPrefersClipasteCloudByDefaultWhenCloudAndLocalAreValid() throws {
    let cloud = standardClipasteCloudURL()
    let local = standardClipasteLocalURL()
    try makeClipasteSchema(at: cloud, records: [
      "public.utf8-plain-text",
      "public.url"
    ])
    try makeClipasteSchema(at: local, records: [
      "public.utf8-plain-text"
    ])

    let candidates = ImportSourceDiscovery(homeDirectory: tempDir).discoverAutomaticSources()
    let cloudCandidate = try XCTUnwrap(candidates.first { $0.kind == .clipasteCloud })
    let localCandidate = try XCTUnwrap(candidates.first { $0.kind == .clipasteLocal })

    XCTAssertTrue(cloudCandidate.isDefaultSelected)
    XCTAssertFalse(localCandidate.isDefaultSelected)
    XCTAssertEqual(cloudCandidate.recordCount, 2)
    XCTAssertEqual(localCandidate.recordCount, 1)
    XCTAssertEqual(cloudCandidate.typeDistribution, [
      "public.utf8-plain-text": 1,
      "public.url": 1
    ])
  }

  func testFallsBackToClipasteLocalDefaultWhenCloudIsMissingOrInvalid() throws {
    try createDB(at: standardClipasteCloudURL(), sql: "CREATE TABLE notes (id INTEGER PRIMARY KEY)")
    try makeClipasteSchema(at: standardClipasteLocalURL())

    let candidates = ImportSourceDiscovery(homeDirectory: tempDir).discoverAutomaticSources()

    XCTAssertNil(candidates.first { $0.kind == .clipasteCloud })
    let localCandidate = try XCTUnwrap(candidates.first { $0.kind == .clipasteLocal })
    XCTAssertTrue(localCandidate.isDefaultSelected)
    XCTAssertEqual(localCandidate.schemaKind, .clipaste)
    XCTAssertEqual(localCandidate.schemaStatus, "OK")
  }

  private func standardMaccyURL() -> URL {
    tempDir.appendingPathComponent(
      "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
    )
  }

  private func standardClipasteCloudURL() -> URL {
    tempDir.appendingPathComponent(
      "Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-cloud.store"
    )
  }

  private func standardClipasteLocalURL() -> URL {
    tempDir.appendingPathComponent(
      "Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-local.store"
    )
  }

  private func makeMaccySchema(at url: URL) throws {
    try createDB(at: url, sql: """
      CREATE TABLE ZHISTORYITEM (
        Z_PK INTEGER PRIMARY KEY,
        ZFIRSTCOPIEDAT REAL,
        ZLASTCOPIEDAT REAL,
        ZNUMBEROFCOPIES INTEGER,
        ZAPPLICATION TEXT,
        ZPIN TEXT,
        ZTITLE TEXT
      );
      CREATE TABLE ZHISTORYITEMCONTENT (
        Z_PK INTEGER PRIMARY KEY,
        ZITEM INTEGER,
        ZTYPE TEXT,
        ZVALUE BLOB
      );
      """)
  }

  private func makeClipasteSchema(at url: URL, records: [String] = []) throws {
    let inserts = records.enumerated()
      .map { index, record in
        "INSERT INTO ZCLIPBOARDRECORD (Z_PK, ZTYPERAWVALUE) VALUES (\(index + 1), '\(record)');"
      }
      .joined(separator: "\n")

    try createDB(at: url, sql: """
      CREATE TABLE ZCLIPBOARDRECORD (
        Z_PK INTEGER PRIMARY KEY,
        ZID TEXT,
        ZTIMESTAMP REAL,
        ZTYPERAWVALUE TEXT,
        ZPLAINTEXT TEXT,
        ZCONTENTHASH TEXT,
        ZISPINNED INTEGER,
        ZGROUPID TEXT,
        ZGROUPIDSRAW TEXT
      );
      CREATE TABLE ZCLIPBOARDGROUPMODEL (
        Z_PK INTEGER PRIMARY KEY,
        ZID TEXT,
        ZNAME TEXT
      );
      \(inserts)
      """)
  }

  private func createDB(at url: URL, sql: String) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }

    var error: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &error)
    if rc != SQLITE_OK {
      let message = error.map { String(cString: $0) } ?? "rc=\(rc)"
      sqlite3_free(error)
      XCTFail(message)
    }
  }
}
