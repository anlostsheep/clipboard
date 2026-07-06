import AppKit
import XCTest
@testable import ClipboardApp

final class StatusBarControllerTests: XCTestCase {
    func testMissingCurrentEventFallsBackToOpeningPanel() {
        XCTAssertEqual(StatusBarController.clickAction(for: nil, modifiers: []), .openPanel)
    }

    func testRightMouseUpShowsMenu() {
        XCTAssertEqual(StatusBarController.clickAction(for: .rightMouseUp, modifiers: []), .showMenu)
    }

    func testLeftMouseUpOpensPanel() {
        XCTAssertEqual(StatusBarController.clickAction(for: .leftMouseUp, modifiers: []), .openPanel)
    }

    func testLeftClickWithoutModifiersOpensPanel() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: []),
            .openPanel)
    }

    func testRightClickShowsMenuRegardlessOfModifiers() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .rightMouseUp, modifiers: [.option]),
            .showMenu)
    }

    func testOptionLeftClickTogglesPause() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.option]),
            .togglePause)
    }

    func testOptionShiftLeftClickIgnoresNextCopy() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.option, .shift]),
            .ignoreNextCopy)
    }

    func testOtherModifierCombinationsOpenPanel() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.command]),
            .openPanel)
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.shift]),
            .openPanel)
    }

    func testNilEventTypeDefaultsToOpenPanel() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: nil, modifiers: [.option]),
            .openPanel)
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
