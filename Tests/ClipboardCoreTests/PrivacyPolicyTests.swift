import XCTest
@testable import ClipboardCore

final class PrivacyPolicyTests: XCTestCase {
  func testStandardPolicyIgnoresConcealedAndTransientTypes() {
    let policy = PrivacyPolicy.standard

    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.nspasteboard.ConcealedType"], sourceBundleId: nil))
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.nspasteboard.TransientType"], sourceBundleId: nil))
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.chromium.web-custom-data"], sourceBundleId: nil))
    XCTAssertFalse(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"], sourceBundleId: nil))
  }

  func testStandardPolicyDoesNotIgnoreUsefulImageWithChromiumTransientMetadata() {
    let policy = PrivacyPolicy.standard

    XCTAssertFalse(policy.shouldIgnore(
      pasteboardTypes: ["public.tiff", "org.chromium.web-custom-data"],
      sourceBundleId: "com.google.Chrome"
    ))
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
