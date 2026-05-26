import XCTest
@testable import ClipboardApp
@testable import ClipboardCore

@MainActor
final class SourceAppIconProviderTests: XCTestCase {
  func testUniversalClipboardRecordDoesNotUseStoredSourceAppBundleIcon() {
    let provider = SourceAppIconProvider()
    let record = ClipboardRecord(
      id: UUID(),
      contentHash: "universal",
      primaryType: .text,
      title: "Phone text",
      plainTextPreview: "Phone text",
      sourceAppBundleId: "com.apple.finder",
      sourceAppName: "Finder",
      sourceDeviceHint: .universalClipboard,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: ["com.apple.is-remote-clipboard"]
    )

    XCTAssertNil(provider.icon(for: record))
  }
}
