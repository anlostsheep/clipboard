import XCTest
@testable import ClipboardCore

final class CaptureControlServiceTests: XCTestCase {
  func testPausedCaptureSkipsAndRecordsReason() async {
    let service = CaptureControlService(policy: .standard)
    await service.pauseCapture()

    let decision = await service.evaluate(makeCapture())
    let capturePaused = await service.capturePaused
    let lastSkipReason = await service.lastSkipReason

    XCTAssertEqual(decision, .skip(.paused))
    XCTAssertTrue(capturePaused)
    XCTAssertEqual(lastSkipReason, .paused)
  }

  func testResumeAllowsCaptureAndClearsSkipReason() async {
    let service = CaptureControlService(policy: .standard)
    await service.pauseCapture()
    _ = await service.evaluate(makeCapture())

    await service.resumeCapture()
    let decision = await service.evaluate(makeCapture())
    let capturePaused = await service.capturePaused
    let lastSkipReason = await service.lastSkipReason

    XCTAssertEqual(decision, .allow)
    XCTAssertFalse(capturePaused)
    XCTAssertNil(lastSkipReason)
  }

  func testIgnoreNextCopySkipsExactlyOnce() async {
    let service = CaptureControlService(policy: .standard)
    await service.ignoreNextCopy()

    let first = await service.evaluate(makeCapture(text: "first"))
    let second = await service.evaluate(makeCapture(text: "second"))
    let lastSkipReason = await service.lastSkipReason

    XCTAssertEqual(first, .skip(.ignoreNextCopy))
    XCTAssertEqual(second, .allow)
    XCTAssertNil(lastSkipReason)
  }

  func testUniversalClipboardSettingSkipsRemoteCapture() async {
    var policy = PrivacyPolicy.standard
    policy.recordsUniversalClipboard = false
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(makeCapture(types: [
      "public.utf8-plain-text",
      "com.apple.is-remote-clipboard"
    ]))
    let lastSkipReason = await service.lastSkipReason

    XCTAssertEqual(decision, .skip(.privacy(.universalClipboard)))
    XCTAssertEqual(lastSkipReason, .privacy(.universalClipboard))
  }

  func testIgnoredPasteboardTypeUsesSortedFirstMatch() async {
    var policy = PrivacyPolicy.standard
    policy.ignoredPasteboardTypes = ["com.example.z-secret", "com.example.a-secret"]
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(makeCapture(types: [
      "public.utf8-plain-text",
      "com.example.z-secret",
      "com.example.a-secret"
    ]))

    XCTAssertEqual(decision, .skip(.privacy(.pasteboardType("com.example.a-secret"))))
  }

  func testIgnoredAppBundleIdSkipsCapture() async {
    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.example.Secret")
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(makeCapture(sourceAppBundleId: "com.example.Secret"))

    XCTAssertEqual(decision, .skip(.privacy(.sourceApp("com.example.Secret"))))
  }

  func testTransientOnlyCaptureSkipsWhenAllTypesAreIgnoredTransientTypes() async {
    var policy = PrivacyPolicy.standard
    policy.ignoredPasteboardTypes = []
    policy.ignoredTransientTypes = ["com.example.transient", "com.example.generated"]
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(makeCapture(types: [
      "com.example.generated",
      "com.example.transient"
    ]))

    XCTAssertEqual(decision, .skip(.privacy(.transientOnly)))
  }

  func testLivePolicyUpdateChangesFutureDecisions() async {
    let service = CaptureControlService(policy: .standard)
    let capture = makeCapture(sourceAppBundleId: "com.example.Secret")

    let firstDecision = await service.evaluate(capture)
    XCTAssertEqual(firstDecision, .allow)

    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.example.Secret")
    await service.updatePolicy(policy)

    let secondDecision = await service.evaluate(capture)
    XCTAssertEqual(secondDecision, .skip(.privacy(.sourceApp("com.example.Secret"))))
  }
}

private func makeCapture(
  text: String = "clipboard text",
  types: Set<String> = ["public.utf8-plain-text"],
  sourceAppBundleId: String? = "com.example.Source"
) -> ClipboardCapture {
  ClipboardCapture(
    payload: .text(text),
    pasteboardTypes: types,
    sourceAppBundleId: sourceAppBundleId,
    sourceAppName: "Source",
    capturedAt: Date(timeIntervalSince1970: 1)
  )
}
