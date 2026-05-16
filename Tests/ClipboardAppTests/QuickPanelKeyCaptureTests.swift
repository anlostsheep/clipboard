import AppKit
import Carbon
import XCTest
@testable import ClipboardApp

final class QuickPanelKeyCaptureTests: XCTestCase {
    func testCommandFRequestsSearchFocus() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_ANSI_F),
            modifierFlags: [.command]
        )

        XCTAssertEqual(action, .focusSearch)
    }

    func testCommandCommaRequestsSettings() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_ANSI_Comma),
            modifierFlags: [.command]
        )

        XCTAssertEqual(action, .openSettings)
    }

    func testArrowKeysMoveSelection() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(keyCode: UInt16(kVK_DownArrow), modifierFlags: []),
            .move(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(keyCode: UInt16(kVK_UpArrow), modifierFlags: []),
            .move(-1)
        )
    }

    func testReturnAndKeypadEnterSubmitSelection() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(keyCode: UInt16(kVK_Return), modifierFlags: []),
            .submit
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifierFlags: []),
            .submit
        )
    }

    func testPlainFIsNotCaptured() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(keyCode: UInt16(kVK_ANSI_F), modifierFlags: [])
        )
    }
}
