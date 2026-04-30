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
    default:
      print("usage: ClipboardManualProbe read-once|write-marker-text|accessibility|self-check")
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
    case let .richText(plainText, rtfData):
      print("payload: richText")
      print("plainTextBytes: \(plainText.utf8.count)")
      print("rtfBytes: \(rtfData.count)")
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
}
