import XCTest
@testable import ClipboardCore

final class ClipboardRecordTests: XCTestCase {
  func testRecordKeepsLargeTextMetadataOutOfTitle() {
    let metadata = LargeTextMetadata(
      byteSize: 10_485_760,
      lineCountEstimate: 42_000,
      contentClass: .json,
      previewExcerpt: "{\"items\": [",
      tailExcerpt: "]}"
    )

    let record = ClipboardRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      contentHash: "abc123",
      primaryType: .text,
      title: "Large JSON",
      plainTextPreview: "{\"items\": [",
      sourceAppBundleId: "com.apple.Terminal",
      sourceAppName: "Terminal",
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: metadata,
      pasteboardTypes: ["public.utf8-plain-text"]
    )

    XCTAssertEqual(record.title, "Large JSON")
    XCTAssertTrue(record.isLargeContent)
    XCTAssertEqual(record.metadata?.contentClass, .json)
  }

  func testCaptureMarksUniversalClipboard() {
    let capture = ClipboardCapture(
      payload: .text("hello"),
      pasteboardTypes: ["public.utf8-plain-text", "com.apple.is-remote-clipboard"],
      sourceAppBundleId: nil,
      sourceAppName: nil,
      capturedAt: Date(timeIntervalSince1970: 2)
    )

    XCTAssertTrue(capture.isUniversalClipboard)
  }
}
