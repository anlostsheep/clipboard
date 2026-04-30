import XCTest
@testable import ClipboardPlatform

final class ClipboardPlatformSmokeTests: XCTestCase {
  func testPlatformTargetLoads() {
    XCTAssertNotNil(SystemPasteboardClient())
  }
}
