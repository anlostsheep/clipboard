import XCTest
@testable import ClipboardCore

final class LargeTextPolicyTests: XCTestCase {
  func testExtremeTextUsesSummaryOnlyPolicy() {
    let policy = LargeTextPolicy(largeTextBytes: 64, extremeTextBytes: 128, excerptLimit: 32)
    let text = String(repeating: "line: value\n", count: 20)
    let result = policy.classify(text: text)

    XCTAssertTrue(result.isLarge)
    XCTAssertEqual(result.metadata?.blobStoragePolicy, .summaryOnly)
    XCTAssertEqual(result.metadata?.indexingState, .excerptIndexed)
    XCTAssertLessThanOrEqual(result.metadata?.previewExcerpt.count ?? 0, 32)
    XCTAssertLessThanOrEqual(result.metadata?.tailExcerpt.count ?? 0, 32)
  }

  func testJsonContentClassIsDetectedFromPrefix() {
    let text = "{\"items\":[1,2,3]}"
    let result = LargeTextPolicy.default.classify(text: text)

    XCTAssertEqual(result.contentClass, .json)
  }
}
