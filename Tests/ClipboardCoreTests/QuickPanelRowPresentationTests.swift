import XCTest
@testable import ClipboardCore

final class QuickPanelRowPresentationTests: XCTestCase {
  func testAllRecordTypesUseSourceAppIconColumn() {
    XCTAssertEqual(QuickPanelRowPresentation.sourceVisual(for: makeRecord(primaryType: .text)), .sourceAppIcon)
    XCTAssertEqual(QuickPanelRowPresentation.sourceVisual(for: makeRecord(primaryType: .image)), .sourceAppIcon)
  }

  func testContentVisualUsesImagePreviewOnlyForImageRecords() {
    XCTAssertEqual(QuickPanelRowPresentation.contentVisual(for: makeRecord(primaryType: .text)), .text)
    XCTAssertEqual(QuickPanelRowPresentation.contentVisual(for: makeRecord(primaryType: .image)), .imagePreview)
  }

  func testSourceNameIsShownInSourceColumnForCompactRows() {
    XCTAssertTrue(QuickPanelRowPresentation.showsSourceName(for: makeRecord(primaryType: .text)))
    XCTAssertTrue(QuickPanelRowPresentation.showsSourceName(for: makeRecord(primaryType: .image)))
  }

  func testUniversalClipboardSourceNameOverridesStaleForegroundAppName() {
    let record = makeRecord(
      primaryType: .text,
      sourceAppName: "VS Code",
      sourceDeviceHint: .universalClipboard
    )

    XCTAssertEqual(QuickPanelRowPresentation.sourceName(for: record), "Universal Clipboard")
  }

  func testUniversalClipboardUsesDeviceFallbackSymbol() {
    let record = makeRecord(primaryType: .text, sourceDeviceHint: .universalClipboard)

    XCTAssertEqual(QuickPanelRowPresentation.sourceFallbackSymbolName(for: record), "iphone")
  }

  func testPrimaryContentTextPrefersPreviewOverTitle() {
    let record = makeRecord(
      primaryType: .text,
      title: "duplicated title",
      plainTextPreview: "single visible clipboard text"
    )

    XCTAssertEqual(QuickPanelRowPresentation.primaryContentText(for: record), "single visible clipboard text")
  }

  func testPrimaryContentTextFallsBackToTitleWhenPreviewIsEmpty() {
    let record = makeRecord(
      primaryType: .text,
      title: "fallback title",
      plainTextPreview: " "
    )

    XCTAssertEqual(QuickPanelRowPresentation.primaryContentText(for: record), "fallback title")
  }

  private func makeRecord(
    primaryType: ClipboardContentType,
    title: String? = nil,
    plainTextPreview: String? = nil,
    sourceAppName: String? = nil,
    sourceDeviceHint: ClipboardSourceDeviceHint = .local
  ) -> ClipboardRecord {
    ClipboardRecord(
      id: UUID(),
      contentHash: primaryType.rawValue,
      primaryType: primaryType,
      title: title ?? primaryType.rawValue,
      plainTextPreview: plainTextPreview,
      sourceAppBundleId: nil,
      sourceAppName: sourceAppName,
      sourceDeviceHint: sourceDeviceHint,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: []
    )
  }
}
