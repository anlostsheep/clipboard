import XCTest
@testable import ClipboardApp

@MainActor
final class AccessibilityPermissionStateTests: XCTestCase {
    func testResolverTreatsFreshProcessRevocationAsUnauthorized() {
        XCTAssertFalse(
            AccessibilityAuthorizationProbe.resolve(
                currentProcessTrusted: true,
                freshProcessTrusted: false
            )
        )
    }

    func testResolverFallsBackToCurrentProcessWhenFreshCheckIsUnavailable() {
        XCTAssertTrue(
            AccessibilityAuthorizationProbe.resolve(
                currentProcessTrusted: true,
                freshProcessTrusted: nil
            )
        )
    }

    func testRefreshUpdatesAuthorizationFromChecker() {
        var isTrusted = false
        let state = AccessibilityPermissionState(checkAuthorization: { isTrusted })

        XCTAssertFalse(state.isAuthorized)

        isTrusted = true
        state.refresh()

        XCTAssertTrue(state.isAuthorized)
    }
}
