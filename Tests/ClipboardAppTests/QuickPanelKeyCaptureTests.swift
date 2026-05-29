import AppKit
import Carbon
import XCTest
@testable import ClipboardApp

final class QuickPanelKeyCaptureTests: XCTestCase {
    func testCommandFSelectsFourthPinnedShortcutInsideQuickPanel() {
        let action = QuickPanelKeyCaptureView.keyboardAction(
            keyCode: UInt16(kVK_ANSI_F),
            modifierFlags: [.command]
        )

        XCTAssertEqual(action, .selectPinnedShortcut(3))
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

    func testCommandNumberSelectsHistoryShortcut() {
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

    func testCommandLettersSelectPinnedShortcutSlots() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.command]
            ),
            .selectPinnedShortcut(0)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_S),
                modifierFlags: [.command]
            ),
            .selectPinnedShortcut(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_L),
                modifierFlags: [.command]
            ),
            .selectPinnedShortcut(8)
        )
    }

    func testPinnedLetterShortcutsRequireExactCommandModifier() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: []
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.shift, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.control, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.option, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_F),
                modifierFlags: [.shift, .command]
            )
        )
    }

    func testTrackedControlCommandPinnedLetterDoesNotFallBackToCommandSelection() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.command],
                trackedModifierFlags: [.control, .command]
            )
        )
    }

    func testCommandQAndCommandCommaKeepReservedQuickPanelActions() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Q),
                modifierFlags: [.command]
            ),
            .quit
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Comma),
                modifierFlags: [.command]
            ),
            .openSettings
        )
    }

    func testControlCommandNumberPastesHistoryShortcut() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.control, .command]
            ),
            .pasteNumber(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_9),
                modifierFlags: [.control, .command]
            ),
            .pasteNumber(9)
        )
    }

    func testControlCommandNumberUsesTrackedModifierFlagsWhenKeyDownDropsControl() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.command],
                trackedModifierFlags: [.control, .command]
            ),
            .pasteNumber(6)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.numberShortcutMode(
                modifierFlags: [.command],
                trackedModifierFlags: [.control, .command]
            ),
            .paste
        )
    }

    func testNumberShortcutsIgnoreStaleTrackedModifiersWhenCurrentEventHasNoShortcutModifiers() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [],
                trackedModifierFlags: [.control, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.numberShortcutMode(
                modifierFlags: [],
                trackedModifierFlags: [.control, .command]
            )
        )
    }

    func testModifierTrackerResetPreventsStaleControlFromPromotingCommandNumber() {
        var tracker = QuickPanelModifierTracker()
        tracker.observe([.control, .command])
        let staleTrackedFlags = tracker.trackedModifierFlags(
            eventModifierFlags: [.command],
            globalModifierFlags: []
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.command],
                trackedModifierFlags: staleTrackedFlags
            ),
            .pasteNumber(6)
        )

        XCTAssertTrue(tracker.resetIfNeeded(token: 1))
        let resetTrackedFlags = tracker.trackedModifierFlags(
            eventModifierFlags: [.command],
            globalModifierFlags: []
        )

        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.command],
                trackedModifierFlags: resetTrackedFlags
            ),
            .selectNumber(6)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.numberShortcutMode(
                modifierFlags: [.command],
                trackedModifierFlags: resetTrackedFlags
            ),
            .select
        )
    }

    func testOptionNumberIsNotCapturedForPaste() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.option]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.option]
            )
        )
    }

    func testNumberShortcutsIgnoreNonSemanticModifierNoise() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.control, .command, .numericPad]
            ),
            .pasteNumber(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_9),
                modifierFlags: [.command, .capsLock, .function]
            ),
            .selectNumber(9)
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.option, .command, .numericPad]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.control, .option, .command]
            )
        )
    }

    func testNumberShortcutHintModeTracksCommandAndControlCommandOnly() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.numberShortcutMode(modifierFlags: [.command, .capsLock]),
            .select
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.numberShortcutMode(modifierFlags: [.control, .command, .numericPad]),
            .paste
        )
        XCTAssertNil(QuickPanelKeyCaptureView.numberShortcutMode(modifierFlags: [.option, .numericPad]))
        XCTAssertNil(QuickPanelKeyCaptureView.numberShortcutMode(modifierFlags: [.option, .shift]))
        XCTAssertNil(QuickPanelKeyCaptureView.numberShortcutMode(modifierFlags: [.command, .option]))
    }

    func testReservedShortcutsPreemptMarkedTextInput() {
        XCTAssertFalse(
            QuickPanelKeyCaptureView.shouldDeferToMarkedTextInput(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.control, .command],
                hasMarkedText: true
            )
        )
        XCTAssertTrue(
            QuickPanelKeyCaptureView.shouldDeferToMarkedTextInput(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.option],
                hasMarkedText: true
            )
        )
        XCTAssertTrue(
            QuickPanelKeyCaptureView.shouldDeferToMarkedTextInput(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.option],
                hasMarkedText: true
            )
        )
        XCTAssertFalse(
            QuickPanelKeyCaptureView.shouldDeferToMarkedTextInput(
                keyCode: UInt16(kVK_ANSI_A),
                modifierFlags: [.option],
                hasMarkedText: false
            )
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
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.control]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.shift, .control, .command]
            )
        )
    }
}
