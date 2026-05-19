import ClipboardCore
import XCTest
@testable import ClipboardApp

final class PrivacySettingsViewTests: XCTestCase {
    func testPrivacyPolicyDisablesUniversalClipboardWhenConfigured() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: ClipboardAppSettings.ignoreUniversalClipboardKey)

        let policy = ClipboardAppSettings.privacyPolicy(defaults: defaults)

        XCTAssertFalse(policy.recordsUniversalClipboard)
    }

    func testPrivacyPolicyAppendsIgnoredPasteboardTypesAndPreservesStandardConcealedType() {
        let defaults = makeDefaults()
        defaults.set(["com.example.secret"], forKey: ClipboardAppSettings.ignoredPasteboardTypesKey)

        let policy = ClipboardAppSettings.privacyPolicy(defaults: defaults)

        XCTAssertTrue(policy.ignoredPasteboardTypes.contains("com.example.secret"))
        XCTAssertTrue(policy.ignoredPasteboardTypes.contains("org.nspasteboard.ConcealedType"))
    }

    func testPrivacyPolicyAppendsIgnoredAppBundleIDs() {
        let defaults = makeDefaults()
        defaults.set(["com.example.Passwords"], forKey: ClipboardAppSettings.ignoredAppBundleIDsKey)

        let policy = ClipboardAppSettings.privacyPolicy(defaults: defaults)

        XCTAssertTrue(policy.ignoredAppBundleIds.contains("com.example.Passwords"))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PrivacySettingsViewTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
