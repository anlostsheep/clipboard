import XCTest
import Carbon
@testable import ClipboardCore

// HotKeyConflictDetector lives in ClipboardCore so it can be unit-tested
// without depending on the ClipboardApp executable target (Swift PM restriction:
// executableTargets cannot be imported by other targets).
//
// The Carbon event-loop registration itself (HotKeyManager) stays in ClipboardApp
// and is covered by manual acceptance tests.

final class HotKeyManagerTests: XCTestCase {

    func testSystemBlacklist_cmdQ_isBlacklisted() {
        let isBlacklisted = HotKeyConflictDetector.isSystemBlacklisted(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(isBlacklisted, "Cmd+Q must be in the system blacklist")
    }

    func testSystemBlacklist_cmdShiftV_isNotBlacklisted() {
        let isBlacklisted = HotKeyConflictDetector.isSystemBlacklisted(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        XCTAssertFalse(isBlacklisted, "Cmd+Shift+V should not be in the system blacklist")
    }

    func testSystemBlacklist_cmdW_isBlacklisted() {
        let isBlacklisted = HotKeyConflictDetector.isSystemBlacklisted(
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(isBlacklisted, "Cmd+W must be in the system blacklist")
    }

    func testSystemBlacklist_cmdTab_isBlacklisted() {
        let isBlacklisted = HotKeyConflictDetector.isSystemBlacklisted(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(isBlacklisted, "Cmd+Tab must be in the system blacklist")
    }
}
