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

    func testCommandQRequestsQuit() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_ANSI_Q),
            modifierFlags: [.command]
        )

        XCTAssertEqual(action, .quit)
    }

    func testCommandShiftQIsNotCapturedByQuickPanel() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Q),
                modifierFlags: [.shift, .command]
            )
        )
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

    func testTabCyclesContentFilterForward() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Tab),
            modifierFlags: []
        )

        XCTAssertEqual(action, .cycleContentFilter(1))
    }

    func testShiftTabCyclesContentFilterBackward() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Tab),
            modifierFlags: [.shift]
        )

        XCTAssertEqual(action, .cycleContentFilter(-1))
    }

    func testModifiedTabCombinationsAreNotCaptured() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.option]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.control]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: [.shift, .command]
            )
        )
    }

    func testPlainFIsNotCaptured() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(keyCode: UInt16(kVK_ANSI_F), modifierFlags: [])
        )
    }

    func testOptionDeleteDeletesSelectedItem() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Delete),
            modifierFlags: [.option]
        )

        XCTAssertEqual(action, .deleteSelected)
    }

    func testOptionCommandDeleteClearsUnpinnedItems() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Delete),
            modifierFlags: [.option, .command]
        )

        XCTAssertEqual(action, .clearUnpinned)
    }

    func testShiftOptionCommandDeleteClearsAllItems() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_Delete),
            modifierFlags: [.shift, .option, .command]
        )

        XCTAssertEqual(action, .clearAll)
    }

    func testOptionPTogglesPinnedItem() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_ANSI_P),
            modifierFlags: [.option]
        )

        XCTAssertEqual(action, .togglePinned)
    }

    func testDestructiveShortcutsRequireExactModifiers() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Delete),
                modifierFlags: [.shift, .option]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Delete),
                modifierFlags: [.control, .option, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_P),
                modifierFlags: [.control, .option]
            )
        )
    }

    func testOptionShiftReturnRequestsPlainTextPaste() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Return),
                modifierFlags: [.option, .shift]
            ),
            .pastePlainText
        )
    }

    func testCommandNumberSelectsVisibleItem() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.command]
            ),
            .selectNumber(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_9),
                modifierFlags: [.command]
            ),
            .selectNumber(9)
        )
    }

    func testOptionNumberPastesVisibleItem() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.option]
            ),
            .pasteNumber(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_9),
                modifierFlags: [.option]
            ),
            .pasteNumber(9)
        )
    }

    func testCommandYRequestsDetailPreview() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Y),
                modifierFlags: [.command]
            ),
            .showDetailPreview
        )
    }

    func testNumberShortcutsRequireExactModifiers() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: []
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.shift, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.shift, .option]
            )
        )
    }
}
