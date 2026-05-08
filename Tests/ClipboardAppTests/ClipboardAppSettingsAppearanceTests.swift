import XCTest
@testable import ClipboardApp

final class ClipboardAppSettingsAppearanceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.appearance.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_appearanceMode_absentDefaultsToSystem() {
        XCTAssertEqual(ClipboardAppSettings.appearanceMode(defaults: defaults), .system)
    }

    func test_appearanceMode_invalidStringDefaultsToSystem() {
        defaults.set("garbage", forKey: ClipboardAppSettings.appearanceModeKey)
        XCTAssertEqual(ClipboardAppSettings.appearanceMode(defaults: defaults), .system)
    }

    func test_appearanceMode_validValueRoundTrips() {
        defaults.set(AppearanceMode.dark.rawValue, forKey: ClipboardAppSettings.appearanceModeKey)
        XCTAssertEqual(ClipboardAppSettings.appearanceMode(defaults: defaults), .dark)
    }
}
