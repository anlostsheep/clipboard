import ClipboardCore
import XCTest
@testable import ClipboardApp

final class PrivacySettingsViewTests: XCTestCase {
    func testCaptureControlPresentationShowsPauseActionWhenCaptureIsRunning() {
        let presentation = PrivacySettingsView.captureControlPresentation(isPaused: false)

        XCTAssertEqual(presentation.statusText, "正在采集")
        XCTAssertEqual(presentation.statusSystemImage, "record.circle")
        XCTAssertEqual(presentation.toggleButtonTitle, "暂停采集")
        XCTAssertEqual(presentation.toggleButtonSystemImage, "pause.circle")
        XCTAssertEqual(presentation.ignoreNextCopyButtonTitle, "忽略下一次复制")
    }

    func testCaptureControlPresentationShowsResumeActionWhenCaptureIsPaused() {
        let presentation = PrivacySettingsView.captureControlPresentation(isPaused: true)

        XCTAssertEqual(presentation.statusText, "已暂停")
        XCTAssertEqual(presentation.statusSystemImage, "pause.circle.fill")
        XCTAssertEqual(presentation.toggleButtonTitle, "恢复采集")
        XCTAssertEqual(presentation.toggleButtonSystemImage, "play.circle")
        XCTAssertEqual(presentation.ignoreNextCopyButtonTitle, "忽略下一次复制")
    }

    func testIgnoredPasteboardTypeEntryUsesInputPlaceholderAndExampleCaption() {
        let presentation = PrivacySettingsView.ignoredPasteboardTypeEntryPresentation()

        XCTAssertEqual(presentation.accessibilityLabel, "排除的剪贴板类型")
        XCTAssertEqual(presentation.inputStyle, .inlinePlain)
        XCTAssertEqual(presentation.placeholder, "输入 pasteboard type")
        XCTAssertEqual(
            presentation.caption,
            "例如 com.example.secret。标准隐藏类型会继续自动过滤；这里用于额外排除自定义 pasteboard type。"
        )
    }

    func testIgnoredAppsSectionUsesApplicationChooserCopy() {
        let presentation = PrivacySettingsView.ignoredAppsSectionPresentation()

        XCTAssertEqual(presentation.title, "不记录这些应用")
        XCTAssertEqual(presentation.chooseButtonTitle, "选择应用...")
        XCTAssertEqual(
            presentation.caption,
            "选择应用后，来自这些应用的剪贴板内容不会进入历史记录。"
        )
    }

    func testIgnoredAppPresentationShowsAppNameAndKeepsBundleIDAsDetail() {
        let presentation = PrivacySettingsView.ignoredAppPresentation(
            bundleID: "com.apple.Safari",
            resolvedAppName: "Safari"
        )

        XCTAssertEqual(presentation.displayName, "Safari")
        XCTAssertEqual(presentation.detail, "com.apple.Safari")
        XCTAssertTrue(presentation.isResolved)
    }

    func testIgnoredAppPresentationFallsBackWhenAppCannotBeResolved() {
        let presentation = PrivacySettingsView.ignoredAppPresentation(
            bundleID: "com.example.Missing",
            resolvedAppName: nil
        )

        XCTAssertEqual(presentation.displayName, "com.example.Missing")
        XCTAssertEqual(presentation.detail, "未找到应用")
        XCTAssertFalse(presentation.isResolved)
    }

    func testPasteboardTypeEntryIsAdvancedByDefault() {
        let presentation = PrivacySettingsView.advancedPasteboardTypePresentation()

        XCTAssertEqual(presentation.title, "高级：排除自定义剪贴板类型")
        XCTAssertFalse(presentation.isExpandedByDefault)
    }

    func testIgnoredEntryAddButtonRequiresNonEmptyInput() {
        XCTAssertFalse(PrivacySettingsView.canAddIgnoredEntry(""))
        XCTAssertFalse(PrivacySettingsView.canAddIgnoredEntry("   \n"))
        XCTAssertTrue(PrivacySettingsView.canAddIgnoredEntry("com.example.Secret"))
    }

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
