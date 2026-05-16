import AppKit
import XCTest
@testable import ClipboardApp

final class StatusBarControllerTests: XCTestCase {
    func testMissingCurrentEventFallsBackToOpeningPanel() {
        XCTAssertEqual(StatusBarController.clickAction(for: nil), .openPanel)
    }

    func testRightMouseUpShowsMenu() {
        XCTAssertEqual(StatusBarController.clickAction(for: .rightMouseUp), .showMenu)
    }

    func testLeftMouseUpOpensPanel() {
        XCTAssertEqual(StatusBarController.clickAction(for: .leftMouseUp), .openPanel)
    }
}
