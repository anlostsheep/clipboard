import AppKit
import ApplicationServices
import ClipboardCore
import Foundation

public final class SystemPasteboardClient: @unchecked Sendable, PasteboardReading, PasteboardWriting, PasteEventPosting {
  private let pasteboard: NSPasteboard
  private let markerType: NSPasteboard.PasteboardType
  private let htmlType = NSPasteboard.PasteboardType("public.html")

  public init(
    pasteboard: NSPasteboard = .general,
    markerType: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType("com.local.clipboard-manager.marker")
  ) {
    self.pasteboard = pasteboard
    self.markerType = markerType
  }

  public func currentChangeCount() async -> Int {
    pasteboard.changeCount
  }

  public func readCurrentCapture() async -> ClipboardCapture? {
    guard let items = pasteboard.pasteboardItems,
          let item = items.first,
          !items.contains(where: containsSelfWriteMarker) else {
      return nil
    }

    let types = Set(items.flatMap { $0.types.map(\.rawValue) })
    let source = sourceApplication(forPasteboardTypes: types)
    let now = Date()

    if let image = firstImagePayload(in: items) {
      return ClipboardCapture(
        payload: .image(data: image.data, uti: image.type.rawValue),
        pasteboardTypes: types,
        sourceAppBundleId: source.bundleID,
        sourceAppName: source.name,
        capturedAt: now
      )
    }

    if let richText = firstRichTextPayload(in: items) {
      return ClipboardCapture(
        payload: .richText(
          plainText: richText.plainText,
          rtfData: richText.rtfData,
          htmlData: richText.htmlData
        ),
        pasteboardTypes: types,
        sourceAppBundleId: source.bundleID,
        sourceAppName: source.name,
        capturedAt: now
      )
    }

    if let string = item.string(forType: .string), !string.isEmpty {
      return ClipboardCapture(
        payload: .text(string),
        pasteboardTypes: types,
        sourceAppBundleId: source.bundleID,
        sourceAppName: source.name,
        capturedAt: now
      )
    }

    let fileURLs = items.compactMap { item -> URL? in
      guard let fileString = item.string(forType: .fileURL) else {
        return nil
      }
      return URL(string: fileString)
    }
    if !fileURLs.isEmpty {
      return ClipboardCapture(
        payload: .fileURLs(fileURLs),
        pasteboardTypes: types,
        sourceAppBundleId: source.bundleID,
        sourceAppName: source.name,
        capturedAt: now
      )
    }

    return nil
  }

  private func sourceApplication(forPasteboardTypes types: Set<String>) -> (bundleID: String?, name: String?) {
    if types.contains("com.apple.is-remote-clipboard") {
      return (nil, "Universal Clipboard")
    }

    let app = NSWorkspace.shared.frontmostApplication
    return (app?.bundleIdentifier, app?.localizedName)
  }

  private func firstRichTextPayload(in items: [NSPasteboardItem]) -> (
    plainText: String,
    rtfData: Data?,
    htmlData: Data?
  )? {
    for item in items {
      let rtfData = item.data(forType: .rtf).flatMap { $0.isEmpty ? nil : $0 }
      let htmlData = item.data(forType: htmlType).flatMap { $0.isEmpty ? nil : $0 }
      guard rtfData != nil || htmlData != nil else {
        continue
      }

      let plainText = item.string(forType: .string)
        ?? rtfData.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil)?.string }
        ?? ""

      return (plainText, rtfData, htmlData)
    }

    return nil
  }

  private func firstImagePayload(in items: [NSPasteboardItem]) -> (data: Data, type: NSPasteboard.PasteboardType)? {
    let imageTypes: [NSPasteboard.PasteboardType] = [
      .png,
      .tiff,
      NSPasteboard.PasteboardType("public.jpeg"),
      NSPasteboard.PasteboardType("public.heic"),
      NSPasteboard.PasteboardType("com.compuserve.gif")
    ]

    for item in items {
      for type in imageTypes {
        if let data = item.data(forType: type), !data.isEmpty {
          return (data, type)
        }
      }
    }

    return nil
  }

  public func write(payload: ClipboardPayload, marker: String) async -> Bool {
    guard let items = makePasteboardItems(payload: payload, marker: marker) else {
      return false
    }

    pasteboard.clearContents()
    return pasteboard.writeObjects(items)
  }

  public func containsMarker(_ marker: String) async -> Bool {
    pasteboard.pasteboardItems?.contains { item in
      item.string(forType: markerType) == marker
    } ?? false
  }

  public func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrustedWithOptions(nil)
  }

  public func requestAccessibilityTrustPrompt() -> Bool {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [promptKey: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  public func openAccessibilitySettings() {
    let urls = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    ]

    for urlString in urls {
      guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else {
        continue
      }
      return
    }
  }

  public func postCommandV() async -> Bool {
    guard isAccessibilityTrusted() else {
      return false
    }

    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
    return keyDown != nil && keyUp != nil
  }

  public func postCommandV(marker: String, pasteboard: any PasteboardWriting) async -> PasteEventResult {
    let targetApp = NSWorkspace.shared.frontmostApplication
    guard await postCommandV() else {
      return .postFailed
    }

    try? await Task.sleep(nanoseconds: 120_000_000)
    guard let targetBundleId = targetApp?.bundleIdentifier,
          let currentBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
      return .posted
    }

    if currentBundleId != targetBundleId,
       currentBundleId != Bundle.main.bundleIdentifier {
      return .targetAppFocusLost
    }

    return .posted
  }

  private func makePasteboardItems(payload: ClipboardPayload, marker: String) -> [NSPasteboardItem]? {
    switch payload {
    case let .text(text):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item),
            item.setString(text, forType: .string) else {
        return nil
      }
      return [item]
    case let .richText(plainText, rtfData, htmlData):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item) else {
        return nil
      }
      let wroteText = item.setString(plainText, forType: .string)
      let wroteRTF = rtfData.map { item.setData($0, forType: .rtf) } ?? false
      let wroteHTML = htmlData.map { item.setData($0, forType: htmlType) } ?? false
      return wroteText || wroteRTF || wroteHTML ? [item] : nil
    case let .image(data, uti):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item),
            item.setData(data, forType: NSPasteboard.PasteboardType(uti)) else {
        return nil
      }
      return [item]
    case let .fileURLs(urls):
      let items = urls.compactMap { url -> NSPasteboardItem? in
        let item = NSPasteboardItem()
        guard setMarker(marker, on: item),
              item.setString(url.absoluteString, forType: .fileURL) else {
          return nil
        }
        return item
      }
      return items.count == urls.count && !items.isEmpty ? items : nil
    }
  }

  private func setMarker(_ marker: String, on item: NSPasteboardItem) -> Bool {
    item.setString(marker, forType: markerType)
  }

  private func containsSelfWriteMarker(_ item: NSPasteboardItem) -> Bool {
    item.string(forType: markerType) != nil
  }
}
