import XCTest
@testable import ClipboardCore

final class ClipboardCoreSmokeTests: XCTestCase {
  func testBootstrapVersionIsStable() {
    XCTAssertEqual(ClipboardCoreBootstrap.version, "0.1.0")
  }
}
