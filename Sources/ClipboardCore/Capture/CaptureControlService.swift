import Foundation

public enum CapturePrivacySkipReason: Equatable, Sendable {
  case universalClipboard
  case pasteboardType(String)
  case sourceApp(String)
  case transientOnly
}

public enum CaptureSkipReason: Equatable, Sendable {
  case paused
  case ignoreNextCopy
  case privacy(CapturePrivacySkipReason)
}

public enum CaptureDecision: Equatable, Sendable {
  case allow
  case skip(CaptureSkipReason)
}

public actor CaptureControlService {
  private var policy: PrivacyPolicy
  private var shouldIgnoreNextCopy = false

  public private(set) var capturePaused = false
  public private(set) var lastSkipReason: CaptureSkipReason?

  public init(policy: PrivacyPolicy, capturePaused: Bool = false) {
    self.policy = policy
    self.capturePaused = capturePaused
  }

  public func pauseCapture() {
    capturePaused = true
  }

  public func resumeCapture() {
    capturePaused = false
  }

  public func ignoreNextCopy() {
    shouldIgnoreNextCopy = true
  }

  public func updatePolicy(_ policy: PrivacyPolicy) {
    self.policy = policy
  }

  public func evaluate(_ capture: ClipboardCapture) -> CaptureDecision {
    if capturePaused {
      return skip(.paused)
    }

    if shouldIgnoreNextCopy {
      shouldIgnoreNextCopy = false
      return skip(.ignoreNextCopy)
    }

    if capture.isUniversalClipboard && !policy.recordsUniversalClipboard {
      return skip(.privacy(.universalClipboard))
    }

    if let sourceAppBundleId = capture.sourceAppBundleId,
       policy.ignoredAppBundleIds.contains(sourceAppBundleId) {
      return skip(.privacy(.sourceApp(sourceAppBundleId)))
    }

    if let ignoredType = capture.pasteboardTypes
      .intersection(policy.ignoredPasteboardTypes)
      .sorted()
      .first {
      return skip(.privacy(.pasteboardType(ignoredType)))
    }

    if !capture.pasteboardTypes.isEmpty &&
      capture.pasteboardTypes.isSubset(of: policy.ignoredTransientTypes) {
      return skip(.privacy(.transientOnly))
    }

    lastSkipReason = nil
    return .allow
  }

  private func skip(_ reason: CaptureSkipReason) -> CaptureDecision {
    lastSkipReason = reason
    return .skip(reason)
  }
}
