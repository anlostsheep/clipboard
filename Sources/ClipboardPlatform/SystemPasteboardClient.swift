import AppKit
import ApplicationServices
import ClipboardCore
import Foundation

public final class SystemPasteboardClient: @unchecked Sendable, PasteboardReading, PasteboardWriting, PasteEventPosting {
  private let pasteboard: NSPasteboard
  private let markerType: NSPasteboard.PasteboardType

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
    let app = NSWorkspace.shared.frontmostApplication
    let now = Date()

    if let string = item.string(forType: .string), !string.isEmpty {
      return ClipboardCapture(
        payload: .text(string),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    if let data = item.data(forType: .png) {
      return ClipboardCapture(
        payload: .image(data: data, uti: NSPasteboard.PasteboardType.png.rawValue),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
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
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
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

  private func makePasteboardItems(payload: ClipboardPayload, marker: String) -> [NSPasteboardItem]? {
    switch payload {
    case let .text(text):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item),
            item.setString(text, forType: .string) else {
        return nil
      }
      return [item]
    case let .richText(plainText, rtfData):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item) else {
        return nil
      }
      let wroteText = item.setString(plainText, forType: .string)
      let wroteRTF = item.setData(rtfData, forType: .rtf)
      return wroteText || wroteRTF ? [item] : nil
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
