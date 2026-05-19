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

    @MainActor
    func testContextMenuIncludesSettingsAction() {
        var didOpenSettings = false
        let controller = StatusBarController(
            onLeftClick: { _ in },
            onQuit: {},
            onOpenSettings: {
                didOpenSettings = true
            }
        )

        let menu = controller.makeContextMenu()
        let settingsItem = menu.items.first { $0.title == "设置..." }
        _ = settingsItem?.target?.perform(settingsItem?.action)

        XCTAssertNotNil(settingsItem)
        XCTAssertTrue(didOpenSettings)
    }
}
