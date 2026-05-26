import AppKit
import ClipboardCore
import ClipboardPlatform
import Darwin
import Foundation

@main
struct ClipboardManualProbe {
  static func main() async {
    let command = CommandLine.arguments.dropFirst().first ?? "read-once"
    let client = SystemPasteboardClient()

    switch command {
    case "read-once":
      await readOnce(client: client)
    case "write-marker-text":
      let text = CommandLine.arguments.dropFirst(2).first ?? "clipboard-manager-manual-probe"
      let wrote = await client.write(payload: .text(text), marker: "manual-probe-marker")
      print(wrote ? "write-marker-text: ok" : "write-marker-text: failed")
    case "accessibility":
      print(client.isAccessibilityTrusted() ? "accessibility: authorized" : "accessibility: required")
    case "self-check":
      let wrote = await client.write(payload: .text("clipboard-manager-self-check"), marker: "manual-probe-marker")
      let hasMarker = await client.containsMarker("manual-probe-marker")
      print("write: \(wrote ? "ok" : "failed")")
      print("marker: \(hasMarker ? "present" : "missing")")
      print(client.isAccessibilityTrusted() ? "accessibility: authorized" : "accessibility: required")
    case "policy-universal-ignore":
      var policy = PrivacyPolicy.standard
      policy.recordsUniversalClipboard = false
      let service = CaptureControlService(policy: policy)
      let decision = await service.evaluate(ClipboardCapture(
        payload: .text("remote"),
        pasteboardTypes: ["com.apple.is-remote-clipboard"],
        sourceAppBundleId: nil,
        sourceAppName: nil,
        capturedAt: Date()
      ))
      print("decision: \(describe(decision))")
    case "policy-ignore-type":
      let ignoredType = CommandLine.arguments.dropFirst(2).first ?? "com.example.secret"
      var policy = PrivacyPolicy.standard
      policy.ignoredPasteboardTypes.insert(ignoredType)
      let service = CaptureControlService(policy: policy)
      let decision = await service.evaluate(ClipboardCapture(
        payload: .text("typed"),
        pasteboardTypes: [ignoredType],
        sourceAppBundleId: nil,
        sourceAppName: nil,
        capturedAt: Date()
      ))
      print("decision: \(describe(decision))")
    case "policy-ignore-app":
      let ignoredBundleID = CommandLine.arguments.dropFirst(2).first ?? "com.example.Passwords"
      var policy = PrivacyPolicy.standard
      policy.ignoredAppBundleIds.insert(ignoredBundleID)
      let service = CaptureControlService(policy: policy)
      let decision = await service.evaluate(ClipboardCapture(
        payload: .text("app"),
        pasteboardTypes: ["public.utf8-plain-text"],
        sourceAppBundleId: ignoredBundleID,
        sourceAppName: "Ignored App",
        capturedAt: Date()
      ))
      print("decision: \(describe(decision))")
    default:
      print("usage: ClipboardManualProbe read-once|write-marker-text|accessibility|self-check|policy-universal-ignore|policy-ignore-type|policy-ignore-app")
      Darwin.exit(2)
    }
  }

  private static func readOnce(client: SystemPasteboardClient) async {
    guard let capture = await client.readCurrentCapture() else {
      print("capture: empty-or-self-write")
      return
    }

    print("capture: ok")
    print("types: \(capture.pasteboardTypes.sorted().joined(separator: ","))")
    print("sourceApp: \(capture.sourceAppName ?? "unknown")")
    print("universalClipboard: \(capture.isUniversalClipboard)")

    switch capture.payload {
    case let .text(text):
      print("payload: text")
      print("textBytes: \(text.utf8.count)")
      print("textPreview: \(String(text.prefix(120)))")
    case let .richText(plainText, rtfData, htmlData):
      print("payload: richText")
      print("plainTextBytes: \(plainText.utf8.count)")
      print("rtfBytes: \(rtfData?.count ?? 0)")
      print("htmlBytes: \(htmlData?.count ?? 0)")
    case let .image(data, uti):
      print("payload: image")
      print("uti: \(uti)")
      print("imageBytes: \(data.count)")
    case let .fileURLs(urls):
      print("payload: fileURLs")
      print("fileCount: \(urls.count)")
      print("files: \(urls.map(\.path).joined(separator: "|"))")
    }
  }

  private static func describe(_ decision: CaptureDecision) -> String {
    switch decision {
    case .allow:
      return "allow"
    case let .skip(reason):
      return "skip(\(describe(reason)))"
    }
  }

  private static func describe(_ reason: CaptureSkipReason) -> String {
    switch reason {
    case .paused:
      return "paused"
    case .ignoreNextCopy:
      return "ignoreNextCopy"
    case let .privacy(reason):
      return "privacy.\(describe(reason))"
    }
  }

  private static func describe(_ reason: CapturePrivacySkipReason) -> String {
    switch reason {
    case .universalClipboard:
      return "universalClipboard"
    case let .pasteboardType(type):
      return "pasteboardType(\(type))"
    case let .sourceApp(bundleID):
      return "sourceApp(\(bundleID))"
    case .transientOnly:
      return "transientOnly"
    }
  }
}
