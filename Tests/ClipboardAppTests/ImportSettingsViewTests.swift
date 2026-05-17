import XCTest
@testable import ClipboardApp

final class ImportSettingsViewTests: XCTestCase {
    func testSettingsPageIncludesImportPage() {
        XCTAssertTrue(SettingsPage.allCases.contains(.importData))
    }

    func testImportPageUsesImportIcon() {
        XCTAssertEqual(SettingsPage.importData.systemImage, "square.and.arrow.down")
    }
}
