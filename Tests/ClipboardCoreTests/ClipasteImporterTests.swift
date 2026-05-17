import Foundation
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

  func testParsesTextLinkMetadataPinnedTimestampGroupAndSourceID() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    try makeDatabase(
      at: databaseURL,
      groups: [
        group(id: "g1", name: "Research")
      ],
      records: [
        record(
          primaryKey: 10,
          id: "clip-1",
          timestamp: 12_345,
          appBundleID: "com.apple.Safari",
          appName: "Safari",
          contentHash: "hash-1",
          customTitle: nil,
          groupID: "g1",
          groupIDsRaw: nil,
          linkTitle: "Example Link",
          plainText: "https://example.com/article",
          typeRawValue: "link",
          isPinned: true
        )
      ]
    )

    let records = try ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL)

    let record = try XCTUnwrap(records.first)
    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(record.source, .clipasteCloud)
    XCTAssertEqual(record.sourceRecordID, "clip-1")
    XCTAssertEqual(record.payload, .text("https://example.com/article"))
    XCTAssertEqual(record.primaryType, .link)
    XCTAssertEqual(record.pasteboardTypes, ["public.utf8-plain-text"])
    XCTAssertEqual(record.title, "Example Link")
    XCTAssertEqual(record.plainTextPreview, "https://example.com/article")
    XCTAssertEqual(record.sourceAppBundleId, "com.apple.Safari")
    XCTAssertEqual(record.sourceAppName, "Safari")
    XCTAssertEqual(record.createdAt, Date(timeIntervalSinceReferenceDate: 12_345))
    XCTAssertEqual(record.lastCopiedAt, Date(timeIntervalSinceReferenceDate: 12_345))
    XCTAssertTrue(record.isPinned)
    XCTAssertFalse(record.isFavorite)
    XCTAssertEqual(record.groupNames, ["Research"])
    XCTAssertEqual(record.sourceDeviceHint, .imported)
    XCTAssertEqual(record.externalContentHash, "hash-1")
    XCTAssertEqual(record.warnings, [])
  }

  func testParsesCodeAsTextWithWarningAndDefaultGroup() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    try makeDatabase(
      at: databaseURL,
      records: [
        record(
          primaryKey: 11,
          id: nil,
          plainText: "let value = 1",
          typeRawValue: "code"
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteLocal).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.source, .clipasteLocal)
    XCTAssertEqual(record.sourceRecordID, "11")
    XCTAssertEqual(record.payload, .text("let value = 1"))
    XCTAssertEqual(record.primaryType, .text)
    XCTAssertEqual(record.groupNames, ["Clipaste Import"])
    XCTAssertTrue(record.warnings.contains("Clipaste code imported as text"))
  }

  func testParsesRichTextFromRTFDataAndPlainText() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    let rtf = Data("{\\rtf1\\ansi Styled}".utf8)
    try makeDatabase(
      at: databaseURL,
      records: [
        record(
          primaryKey: 12,
          plainText: "Styled body",
          typeRawValue: "richText",
          rtfData: rtf
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .richText(plainText: "Styled body", rtfData: rtf))
    XCTAssertEqual(record.primaryType, .richText)
    XCTAssertEqual(record.pasteboardTypes, ["public.rtf", "public.utf8-plain-text"])
    XCTAssertEqual(record.plainTextPreview, "Styled body")
  }

  func testParsesImageFromImageDataAndUTI() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    let image = Data([0x89, 0x50, 0x4e, 0x47])
    try makeDatabase(
      at: databaseURL,
      records: [
        record(
          primaryKey: 13,
          customTitle: "Screenshot",
          imageUTType: "public.png",
          plainText: "image preview",
          typeRawValue: "image",
          imageData: image
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .image(data: image, uti: "public.png"))
    XCTAssertEqual(record.primaryType, .image)
    XCTAssertEqual(record.pasteboardTypes, ["public.png"])
    XCTAssertEqual(record.title, "Screenshot")
    XCTAssertEqual(record.plainTextPreview, "image preview")
  }

  func testParsesFileURLPlainTextIntoFileURLsPayload() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    try makeDatabase(
      at: databaseURL,
      records: [
        record(
          primaryKey: 14,
          plainText: "file:///Users/lostsheep/Desktop/a.txt\nfile:///tmp/b.png",
          typeRawValue: "fileURL"
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .fileURLs([
      URL(fileURLWithPath: "/Users/lostsheep/Desktop/a.txt"),
      URL(fileURLWithPath: "/tmp/b.png")
    ]))
    XCTAssertEqual(record.primaryType, .file)
    XCTAssertEqual(record.pasteboardTypes, ["public.file-url"])
    XCTAssertEqual(record.title, "file:///Users/lostsheep/Desktop/a.txt\nfile:///tmp/b.png")
    XCTAssertNil(record.plainTextPreview)
  }

  func testPreservesMultipleGroupsFromRawStringWhenAvailable() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    try makeDatabase(
      at: databaseURL,
      groups: [
        group(id: "g1", name: "Work"),
        group(id: "g2", name: "Personal"),
        group(id: "g3", name: "Archive")
      ],
      records: [
        record(
          primaryKey: 15,
          groupID: "g3",
          groupIDsRaw: #"["g1"; "g2", "g1"; "g3", "missing"]"#,
          plainText: "multi group",
          typeRawValue: "text"
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.groupNames, ["Work", "Personal", "Archive"])
  }

  func testParsesBlobSourceIDAsUppercaseHex() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    let idData = Data([
      0x0C, 0xF3, 0x10, 0xA2,
      0x7B, 0x00, 0x4E, 0x9D,
      0x81, 0x22, 0x33, 0x44,
      0x55, 0x66, 0x77, 0x88
    ])
    try makeDatabase(
      at: databaseURL,
      records: [
        record(
          primaryKey: 18,
          idData: idData,
          plainText: "blob id",
          typeRawValue: "text"
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.sourceRecordID, "0CF310A27B004E9D8122334455667788")
  }

  func testValidRowWithoutGroupTableImportsIntoDefaultGroup() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    try makeDatabase(
      at: databaseURL,
      includeGroupsTable: false,
      records: [
        record(
          primaryKey: 19,
          groupID: "g1",
          groupIDsRaw: "g1,g2",
          plainText: "valid without groups",
          typeRawValue: "text"
        )
      ]
    )

    let record = try XCTUnwrap(ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL).first)

    XCTAssertEqual(record.payload, .text("valid without groups"))
    XCTAssertEqual(record.groupNames, ["Clipaste Import"])
  }

  func testSkipsRowsWithUnsupportedOrMissingRequiredPayload() throws {
    let databaseURL = tempDir.appendingPathComponent("clipaste.sqlite")
    try makeDatabase(
      at: databaseURL,
      includeGroupsTable: false,
      records: [
        record(primaryKey: 16, plainText: nil, typeRawValue: "text"),
        record(primaryKey: 17, plainText: "unsupported", typeRawValue: "color")
      ]
    )

    let records = try ClipasteImporter(source: .clipasteCloud).importRecords(from: databaseURL)

    XCTAssertTrue(records.isEmpty)
  }

  private struct Group {
    let id: String
    let name: String
  }

  private struct Record {
    let primaryKey: Int
    let id: String?
    let idData: Data?
    let timestamp: Double
    let appBundleID: String?
    let appName: String?
    let contentHash: String?
    let customTitle: String?
    let groupID: String?
    let groupIDsRaw: String?
    let imageUTType: String?
    let linkTitle: String?
    let plainText: String?
    let typeRawValue: String?
    let isPinned: Bool
    let imageData: Data?
    let rtfData: Data?
  }

  private func group(id: String, name: String) -> Group {
    Group(id: id, name: name)
  }

  private func record(
    primaryKey: Int,
    id: String? = nil,
    idData: Data? = nil,
    timestamp: Double = 1_700_000_001,
    appBundleID: String? = nil,
    appName: String? = nil,
    contentHash: String? = nil,
    customTitle: String? = nil,
    groupID: String? = nil,
    groupIDsRaw: String? = nil,
    imageUTType: String? = nil,
    linkTitle: String? = nil,
    plainText: String? = nil,
    typeRawValue: String? = nil,
    isPinned: Bool = false,
    imageData: Data? = nil,
    rtfData: Data? = nil
  ) -> Record {
    Record(
      primaryKey: primaryKey,
      id: id,
      idData: idData,
      timestamp: timestamp,
      appBundleID: appBundleID,
      appName: appName,
      contentHash: contentHash,
      customTitle: customTitle,
      groupID: groupID,
      groupIDsRaw: groupIDsRaw,
      imageUTType: imageUTType,
      linkTitle: linkTitle,
      plainText: plainText,
      typeRawValue: typeRawValue,
      isPinned: isPinned,
      imageData: imageData,
      rtfData: rtfData
    )
  }

  private func makeDatabase(
    at url: URL,
    includeGroupsTable: Bool = true,
    groups: [Group] = [],
    records: [Record]
  ) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
    defer { sqlite3_close(db) }

    if includeGroupsTable {
      try exec(
        """
        CREATE TABLE ZCLIPBOARDGROUPMODEL (
          Z_PK INTEGER PRIMARY KEY,
          ZID TEXT,
          ZNAME TEXT
        );
        """,
        in: db
      )
    }

    try exec(
      """
      CREATE TABLE ZCLIPBOARDRECORD (
        Z_PK INTEGER PRIMARY KEY,
        ZID TEXT,
        ZTIMESTAMP REAL,
        ZAPPBUNDLEID TEXT,
        ZAPPLOCALIZEDNAME TEXT,
        ZCONTENTHASH TEXT,
        ZCUSTOMTITLE TEXT,
        ZGROUPID TEXT,
        ZGROUPIDSRAW TEXT,
        ZIMAGEUTTYPE TEXT,
        ZLINKTITLE TEXT,
        ZPLAINTEXT TEXT,
        ZTYPERAWVALUE TEXT,
        ZISPINNED INTEGER,
        ZIMAGEDATA BLOB,
        ZRTFDATA BLOB
      );
      """,
      in: db
    )

    for (index, group) in groups.enumerated() {
      try insertGroup(group, primaryKey: index + 1, in: db)
    }

    for record in records {
      try insertRecord(record, in: db)
    }
  }

  private func insertGroup(_ group: Group, primaryKey: Int, in db: OpaquePointer?) throws {
    let sql = "INSERT INTO ZCLIPBOARDGROUPMODEL (Z_PK, ZID, ZNAME) VALUES (?, ?, ?)"
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, Int64(primaryKey))
    bindText(statement, 2, group.id)
    bindText(statement, 3, group.name)
    XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
  }

  private func insertRecord(_ record: Record, in db: OpaquePointer?) throws {
    let sql = """
      INSERT INTO ZCLIPBOARDRECORD
      (Z_PK, ZID, ZTIMESTAMP, ZAPPBUNDLEID, ZAPPLOCALIZEDNAME, ZCONTENTHASH, ZCUSTOMTITLE,
       ZGROUPID, ZGROUPIDSRAW, ZIMAGEUTTYPE, ZLINKTITLE, ZPLAINTEXT, ZTYPERAWVALUE,
       ZISPINNED, ZIMAGEDATA, ZRTFDATA)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """
    var statement: OpaquePointer?
    XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &statement, nil), SQLITE_OK)
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_int64(statement, 1, Int64(record.primaryKey))
    if let idData = record.idData {
      bindData(statement, 2, idData)
    } else {
      bindText(statement, 2, record.id)
    }
    sqlite3_bind_double(statement, 3, record.timestamp)
    bindText(statement, 4, record.appBundleID)
    bindText(statement, 5, record.appName)
    bindText(statement, 6, record.contentHash)
    bindText(statement, 7, record.customTitle)
    bindText(statement, 8, record.groupID)
    bindText(statement, 9, record.groupIDsRaw)
    bindText(statement, 10, record.imageUTType)
    bindText(statement, 11, record.linkTitle)
    bindText(statement, 12, record.plainText)
    bindText(statement, 13, record.typeRawValue)
    sqlite3_bind_int(statement, 14, record.isPinned ? 1 : 0)
    bindData(statement, 15, record.imageData)
    bindData(statement, 16, record.rtfData)
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

  private func bindData(_ statement: OpaquePointer?, _ index: Int32, _ value: Data?) {
    guard let value else {
      sqlite3_bind_null(statement, index)
      return
    }
    let bindResult = value.withUnsafeBytes { buffer in
      sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLiteTransient)
    }
    XCTAssertEqual(bindResult, SQLITE_OK)
  }
}

private let SQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
