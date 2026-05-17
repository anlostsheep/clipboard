import Foundation
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

  func testParsesTextLinkMetadataAndWarnings() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 1,
          firstCopiedAt: 10,
          lastCopiedAt: 20,
          copyCount: 3,
          application: "Safari",
          pin: "pin",
          title: nil,
          contents: [
            content(type: "public.utf8-plain-text", value: "https://example.com/a"),
            content(type: "org.nspasteboard.source", value: "com.apple.Safari"),
            content(type: "com.apple.is-remote-clipboard", value: ""),
            content(type: "com.example.unsupported", value: "ignored")
          ]
        )
      ]
    )

    let records = try MaccyImporter(source: .maccy).importRecords(from: databaseURL)

    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(record.source, .maccy)
    XCTAssertEqual(record.sourceRecordID, "1")
    XCTAssertEqual(record.payload, .text("https://example.com/a"))
    XCTAssertEqual(record.primaryType, .link)
    XCTAssertEqual(record.title, "https://example.com/a")
    XCTAssertEqual(record.plainTextPreview, "https://example.com/a")
    XCTAssertEqual(record.sourceAppBundleId, "com.apple.Safari")
    XCTAssertEqual(record.sourceAppName, "Safari")
    XCTAssertEqual(record.createdAt, Date(timeIntervalSinceReferenceDate: 10))
    XCTAssertEqual(record.lastCopiedAt, Date(timeIntervalSinceReferenceDate: 20))
    XCTAssertEqual(record.copyCount, 3)
    XCTAssertTrue(record.isPinned)
    XCTAssertFalse(record.isFavorite)
    XCTAssertEqual(record.groupNames, ["Maccy Import"])
    XCTAssertEqual(record.sourceDeviceHint, .universalClipboard)
    XCTAssertNil(record.externalContentHash)
    XCTAssertEqual(record.pasteboardTypes, [
      "public.utf8-plain-text",
      "org.nspasteboard.source",
      "com.apple.is-remote-clipboard",
      "com.example.unsupported"
    ])
    XCTAssertEqual(record.warnings, ["Unsupported Maccy pasteboard type: com.example.unsupported"])
  }

  func testPrefersRichPayloadOverTitleFallback() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    let rtf = Data("{\\rtf1\\ansi Hello}".utf8)
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 2,
          firstCopiedAt: 30,
          lastCopiedAt: 40,
          copyCount: 0,
          application: "TextEdit",
          pin: nil,
          title: "Styled Title",
          contents: [
            content(type: "public.rtf", data: rtf),
            content(type: "public.utf8-plain-text", value: "Styled body")
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .manualMaccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.source, .manualMaccy)
    XCTAssertEqual(record.payload, .richText(plainText: "Styled body", rtfData: rtf))
    XCTAssertEqual(record.primaryType, .richText)
    XCTAssertEqual(record.title, "Styled Title")
    XCTAssertEqual(record.plainTextPreview, "Styled body")
    XCTAssertEqual(record.sourceAppName, "TextEdit")
    XCTAssertEqual(record.copyCount, 1)
  }

  func testConvertsMaccyCoreDataReferenceDates() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 6,
          firstCopiedAt: 0,
          lastCopiedAt: 60,
          title: nil,
          contents: [
            content(type: "public.utf8-plain-text", value: "date check")
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .maccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.createdAt, Date(timeIntervalSinceReferenceDate: 0))
    XCTAssertEqual(record.lastCopiedAt, Date(timeIntervalSinceReferenceDate: 60))
  }

  func testUsesApplicationBundleIDWhenPasteboardSourceIsAbsent() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 7,
          application: "com.google.Chrome",
          title: nil,
          contents: [
            content(type: "public.utf8-plain-text", value: "chrome copy")
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .maccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.sourceAppBundleId, "com.google.Chrome")
    XCTAssertNil(record.sourceAppName)
  }

  func testDoesNotUseApplicationBundleIDAsNameWhenPasteboardSourceExists() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 8,
          application: "com.google.Chrome",
          title: nil,
          contents: [
            content(type: "public.utf8-plain-text", value: "chrome source"),
            content(type: "org.nspasteboard.source", value: "com.google.Chrome")
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .maccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.sourceAppBundleId, "com.google.Chrome")
    XCTAssertNil(record.sourceAppName)
  }

  func testParsesFileURLs() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 3,
          title: nil,
          contents: [
            content(
              type: "public.file-url",
              value: "file:///Users/lostsheep/Desktop/a.txt\nfile:///tmp/b.png"
            )
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .maccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .fileURLs([
      URL(fileURLWithPath: "/Users/lostsheep/Desktop/a.txt"),
      URL(fileURLWithPath: "/tmp/b.png")
    ]))
    XCTAssertEqual(record.primaryType, .file)
    XCTAssertEqual(record.title, "a.txt")
    XCTAssertNil(record.plainTextPreview)
  }

  func testSkipsRowsWithNoSupportedPayload() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 4,
          title: "Only title",
          contents: [
            content(type: "com.example.unsupported", value: "ignored")
          ]
        )
      ]
    )

    let records = try MaccyImporter(source: .maccy).importRecords(from: databaseURL)

    XCTAssertTrue(records.isEmpty)
  }

  func testImagePayloadTakesHighestPriority() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    let imageData = Data([0x89, 0x50, 0x4e, 0x47])
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 5,
          title: "Screenshot",
          contents: [
            content(type: "public.utf8-plain-text", value: "text fallback"),
            content(type: "public.png", data: imageData)
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .maccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .image(data: imageData, uti: "public.png"))
    XCTAssertEqual(record.primaryType, .image)
    XCTAssertEqual(record.title, "Screenshot")
    XCTAssertEqual(record.plainTextPreview, "text fallback")
  }

  func testImportsHEICImagePayload() throws {
    let databaseURL = tempDir.appendingPathComponent("maccy.sqlite")
    let imageData = Data([0x00, 0x00, 0x00, 0x18])
    try makeDatabase(
      at: databaseURL,
      items: [
        item(
          id: 9,
          title: "HEIC Image",
          contents: [
            content(type: "public.heic", data: imageData)
          ]
        )
      ]
    )

    let record = try XCTUnwrap(MaccyImporter(source: .maccy).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .image(data: imageData, uti: "public.heic"))
    XCTAssertEqual(record.primaryType, .image)
    XCTAssertEqual(record.pasteboardTypes, ["public.heic"])
    XCTAssertEqual(record.warnings, [])
  }

  private struct Item {
    let id: Int
    let firstCopiedAt: Double
    let lastCopiedAt: Double
    let copyCount: Int
    let application: String?
    let pin: String?
    let title: String?
    let contents: [Content]
  }

  private struct Content {
    let type: String
    let data: Data
  }

  private func item(
    id: Int,
    firstCopiedAt: Double = 1,
    lastCopiedAt: Double = 2,
    copyCount: Int = 1,
    application: String? = nil,
    pin: String? = nil,
    title: String?,
    contents: [Content]
  ) -> Item {
    Item(
      id: id,
      firstCopiedAt: firstCopiedAt,
      lastCopiedAt: lastCopiedAt,
      copyCount: copyCount,
      application: application,
      pin: pin,
      title: title,
      contents: contents
    )
  }

  private func content(type: String, value: String) -> Content {
    Content(type: type, data: Data(value.utf8))
  }

  private func content(type: String, data: Data) -> Content {
    Content(type: type, data: data)
  }

  private func makeDatabase(at url: URL, items: [Item]) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }

    try exec(
      """
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
      """,
      in: db
    )

    var contentID = 1
    for item in items {
      try insertItem(item, in: db)
      for content in item.contents {
        try insertContent(content, id: contentID, itemID: item.id, in: db)
        contentID += 1
      }
    }
  }

  private func insertItem(_ item: Item, in db: OpaquePointer?) throws {
    let sql = """
      INSERT INTO ZHISTORYITEM
      (Z_PK, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT, ZNUMBEROFCOPIES, ZAPPLICATION, ZPIN, ZTITLE)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, Int64(item.id))
    sqlite3_bind_double(statement, 2, item.firstCopiedAt)
    sqlite3_bind_double(statement, 3, item.lastCopiedAt)
    sqlite3_bind_int64(statement, 4, Int64(item.copyCount))
    bindText(statement, 5, item.application)
    bindText(statement, 6, item.pin)
    bindText(statement, 7, item.title)
    XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
  }

  private func insertContent(_ content: Content, id: Int, itemID: Int, in db: OpaquePointer?) throws {
    let sql = """
      INSERT INTO ZHISTORYITEMCONTENT
      (Z_PK, ZITEM, ZTYPE, ZVALUE)
      VALUES (?, ?, ?, ?)
      """
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, Int64(id))
    sqlite3_bind_int64(statement, 2, Int64(itemID))
    bindText(statement, 3, content.type)
    let bindResult = content.data.withUnsafeBytes { buffer in
      sqlite3_bind_blob(statement, 4, buffer.baseAddress, Int32(buffer.count), SQLiteTransient)
    }
    XCTAssertEqual(bindResult, SQLITE_OK)
    XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
  }

  private func exec(_ sql: String, in db: OpaquePointer?) throws {
    var error: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &error)
    if rc != SQLITE_OK {
      let message = error.map { String(cString: $0) } ?? "rc=\(rc)"
      sqlite3_free(error)
      XCTFail(message)
    }
  }

  private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    guard let value else {
      sqlite3_bind_null(statement, index)
      return
    }
    sqlite3_bind_text(statement, index, value, -1, SQLiteTransient)
  }
}

private let SQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
