import Foundation

public enum QuickPanelSourceVisual: Equatable, Sendable {
  case sourceAppIcon
}

public enum QuickPanelContentVisual: Equatable, Sendable {
  case text
  case imagePreview
}

public struct QuickPanelRowPresentation: Sendable {
  public static func sourceVisual(for record: ClipboardRecord) -> QuickPanelSourceVisual {
    .sourceAppIcon
  }

  public static func contentVisual(for record: ClipboardRecord) -> QuickPanelContentVisual {
    record.primaryType == .image ? .imagePreview : .text
  }

  public static func showsSourceName(for record: ClipboardRecord) -> Bool {
    true
  }

  public static func primaryContentText(for record: ClipboardRecord) -> String {
    if let preview = record.plainTextPreview?.trimmingCharacters(in: .whitespacesAndNewlines),
       !preview.isEmpty {
      return preview
    }

    return record.title
  }
}
