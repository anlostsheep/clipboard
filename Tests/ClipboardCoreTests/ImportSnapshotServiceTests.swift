import Foundation
import SQLite3
import XCTest
@testable import ClipboardCore

final class ImportSnapshotServiceTests: XCTestCase {
  private var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-import-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testSnapshotCopiesDatabaseAndSidecarsToTemporaryDirectory() throws {
    let source = tempDir.appendingPathComponent("maccy.sqlite")
    try Data("database".utf8).write(to: source)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: source.path + "-wal"))
    try Data("shm".utf8).write(to: URL(fileURLWithPath: source.path + "-shm"))

    let snapshot = try ImportSnapshotService().snapshot(databaseURL: source)

    XCTAssertNotEqual(snapshot.directoryURL, tempDir)
    XCTAssertEqual(snapshot.databaseURL.lastPathComponent, "maccy.sqlite")
    XCTAssertEqual(try Data(contentsOf: snapshot.databaseURL), Data("database".utf8))
    XCTAssertEqual(
      try Data(contentsOf: snapshot.directoryURL.appendingPathComponent("maccy.sqlite-wal")),
      Data("wal".utf8)
    )
    XCTAssertEqual(
      try Data(contentsOf: snapshot.directoryURL.appendingPathComponent("maccy.sqlite-shm")),
      Data("shm".utf8)
    )
  }

  func testSnapshotRemovesTemporaryDirectoryWhenCopyFailsAfterCreation() throws {
    let before = clipboardImportTemporaryDirectories()
    let missingSource = tempDir.appendingPathComponent("missing.sqlite")

    XCTAssertThrowsError(try ImportSnapshotService().snapshot(databaseURL: missingSource))

    let after = clipboardImportTemporaryDirectories()
    XCTAssertEqual(after, before)
  }

  func testExternalSQLiteDatabaseDetectsFixtureSchemaAndReadsCount() throws {
    let source = tempDir.appendingPathComponent("fixture.sqlite")
    try createFixtureDatabase(at: source)

    let database = try ExternalSQLiteDatabase(path: source.path)

    XCTAssertTrue(try database.hasTable("ZHISTORYITEMCONTENT"))
    XCTAssertEqual(try database.columns(in: "ZHISTORYITEMCONTENT"), ["Z_PK", "ZITEM", "ZTYPE", "ZVALUE"])
    XCTAssertTrue(try database.hasColumns(["ZITEM", "ZTYPE", "ZVALUE"], in: "ZHISTORYITEMCONTENT"))
    XCTAssertEqual(try database.intScalar("SELECT COUNT(*) FROM ZHISTORYITEMCONTENT"), 1)
  }

  func testExternalSQLiteDatabaseRowsCanReadBlobData() throws {
    let source = tempDir.appendingPathComponent("fixture.sqlite")
    try createFixtureDatabase(at: source)
    let database = try ExternalSQLiteDatabase(path: source.path)
    var blob: Data?

    try database.rows("SELECT ZVALUE FROM ZHISTORYITEMCONTENT WHERE Z_PK = 1") { statement in
      blob = statement.columnData(0)
    }

    XCTAssertEqual(blob, Data([0x6d, 0x61, 0x63, 0x63, 0x79]))
  }

  func testExternalSQLiteDatabaseRejectsUnsafeIdentifiers() throws {
    let source = tempDir.appendingPathComponent("fixture.sqlite")
    try createFixtureDatabase(at: source)
    let database = try ExternalSQLiteDatabase(path: source.path)

    XCTAssertThrowsError(try database.columns(in: "ZHISTORYITEMCONTENT; DROP TABLE ZHISTORYITEMCONTENT"))
  }

  private func createFixtureDatabase(at url: URL) throws {
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }

    let sql = """
      CREATE TABLE ZHISTORYITEMCONTENT (
        Z_PK INTEGER PRIMARY KEY,
        ZITEM INTEGER NOT NULL,
        ZTYPE TEXT NOT NULL,
        ZVALUE BLOB
      );
      INSERT INTO ZHISTORYITEMCONTENT (Z_PK, ZITEM, ZTYPE, ZVALUE)
      VALUES (1, 10, 'public.utf8-plain-text', X'6D61636379');
      """

    var error: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &error)
    if rc != SQLITE_OK {
      let message = error.map { String(cString: $0) } ?? "rc=\(rc)"
      sqlite3_free(error)
      XCTFail(message)
    }
  }

  private func clipboardImportTemporaryDirectories() -> Set<String> {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: temporaryDirectory,
      includingPropertiesForKeys: nil
    )) ?? []

    return Set(urls.map(\.lastPathComponent).filter { $0.hasPrefix("clipboard-import-") })
  }
}
