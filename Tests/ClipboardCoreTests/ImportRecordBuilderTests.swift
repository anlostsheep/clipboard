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
    XCTAssertNotEqual(first.contentHash, imported.externalContentHash)
    XCTAssertEqual(first.primaryType, .link)
    XCTAssertEqual(first.title, "Example")
    XCTAssertEqual(first.copyCount, 3)
    XCTAssertEqual(first.isPinned, true)
    XCTAssertEqual(first.retentionExempt, true)
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

  func testRichTextHashMatchesPlainTextHashForSamePlainText() {
    let builder = ImportRecordBuilder()

    let textHash = builder.contentHash(for: .text("same"))
    let richTextHash = builder.contentHash(
      for: .richText(plainText: "same", rtfData: Data([9, 8, 7]))
    )

    XCTAssertEqual(richTextHash, textHash)
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
