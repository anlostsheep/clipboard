import AppKit
import XCTest
@testable import ClipboardApp

final class AppearanceModeTests: XCTestCase {
    func test_nsAppearance_systemReturnsNil() {
        XCTAssertNil(AppearanceMode.system.nsAppearance)
    }

    func test_nsAppearance_lightReturnsAqua() {
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
    }

    func test_nsAppearance_darkReturnsDarkAqua() {
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name, .darkAqua)
    }
}
