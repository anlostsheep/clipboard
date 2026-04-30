import XCTest
@testable import ClipboardCore

final class PerformanceGuardTests: XCTestCase {
  func testTenMegabyteJsonClassificationDoesNotExposeFullPreview() throws {
    let json = "{" + String(repeating: "\"message\":\"hello\",", count: 560_000) + "\"end\":true}"

    XCTAssertGreaterThanOrEqual(json.utf8.count, 10_000_000)

    let result = LargeTextPolicy.default.classify(text: json)
    let metadata = try XCTUnwrap(result.metadata)

    XCTAssertTrue(result.isLarge)
    XCTAssertEqual(result.contentClass, .json)
    XCTAssertLessThanOrEqual(metadata.previewExcerpt.count, 2_048)
    XCTAssertLessThanOrEqual(metadata.tailExcerpt.count, 2_048)
    XCTAssertNotEqual(metadata.previewExcerpt, json)
    XCTAssertNotEqual(metadata.tailExcerpt, json)
  }
}
