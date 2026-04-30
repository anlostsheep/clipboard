import XCTest
@testable import ClipboardCore

final class PrivacyPolicyTests: XCTestCase {
  func testStandardPolicyIgnoresConcealedAndTransientTypes() {
    let policy = PrivacyPolicy.standard

    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.nspasteboard.ConcealedType"], sourceBundleId: nil))
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.nspasteboard.TransientType"], sourceBundleId: nil))
    XCTAssertFalse(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"], sourceBundleId: nil))
  }

  func testUniversalClipboardCanBeDisabled() {
    var policy = PrivacyPolicy.standard
    policy.recordsUniversalClipboard = false

    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text", "com.apple.is-remote-clipboard"], sourceBundleId: nil))
  }

  func testIgnoredAppsAreNotLimitedToApplicationsFolder() {
    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.example.ToolOutsideApplications")

    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"], sourceBundleId: "com.example.ToolOutsideApplications"))
  }
}
