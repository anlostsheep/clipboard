import AppKit
import ClipboardCore

@MainActor
final class SourceAppIconProvider {
  private let iconSize = NSSize(width: 24, height: 24)
  private var iconsByBundleID: [String: NSImage] = [:]

  func icon(for record: ClipboardRecord) -> NSImage? {
    guard let bundleID = record.sourceAppBundleId?.trimmingCharacters(in: .whitespacesAndNewlines),
          !bundleID.isEmpty
    else {
      return nil
    }

    if let cachedIcon = iconsByBundleID[bundleID] {
      return cachedIcon
    }

    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return nil
    }

    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
    icon.size = iconSize
    iconsByBundleID[bundleID] = icon
    return icon
  }
}
