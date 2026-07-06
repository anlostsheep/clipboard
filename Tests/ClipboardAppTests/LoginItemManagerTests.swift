import XCTest
@testable import ClipboardApp

final class LoginItemManagerTests: XCTestCase {
    func testEnabledStatusPresentsToggleOnWithoutHint() {
        let p = LoginItemSettingPresentation.make(from: .enabled)
        XCTAssertTrue(p.isOn)
        XCTAssertTrue(p.isToggleEnabled)
        XCTAssertNil(p.hint)
        XCTAssertFalse(p.showsOpenSettingsButton)
    }

    func testNotRegisteredStatusPresentsToggleOffWithoutHint() {
        let p = LoginItemSettingPresentation.make(from: .notRegistered)
        XCTAssertFalse(p.isOn)
        XCTAssertTrue(p.isToggleEnabled)
        XCTAssertNil(p.hint)
        XCTAssertFalse(p.showsOpenSettingsButton)
    }

    func testRequiresApprovalStatusShowsHintAndSettingsButton() {
        let p = LoginItemSettingPresentation.make(from: .requiresApproval)
        XCTAssertFalse(p.isOn)
        XCTAssertTrue(p.isToggleEnabled)
        XCTAssertNotNil(p.hint)
        XCTAssertTrue(p.showsOpenSettingsButton)
    }

    func testUnsupportedStatusDisablesToggleWithReason() {
        let p = LoginItemSettingPresentation.make(from: .unsupported(reason: "not an app bundle"))
        XCTAssertFalse(p.isOn)
        XCTAssertFalse(p.isToggleEnabled)
        XCTAssertEqual(p.hint, "not an app bundle")
        XCTAssertFalse(p.showsOpenSettingsButton)
    }
}
