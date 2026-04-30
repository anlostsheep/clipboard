import Foundation

public enum ClipboardContentType: String, Codable, Equatable, Sendable {
  case text
  case richText
  case link
  case image
  case file
}

public enum ClipboardSourceDeviceHint: String, Codable, Equatable, Sendable {
  case local
  case universalClipboard
  case imported
}

public enum LargeTextContentClass: String, Codable, Equatable, Sendable {
  case json
  case yaml
  case log
  case plain
  case code
}

public enum BlobStoragePolicy: String, Codable, Equatable, Sendable {
  case full
  case summaryOnly
  case skipped
}

public enum IndexingState: String, Codable, Equatable, Sendable {
  case notIndexed
  case excerptIndexed
  case fullTextQueued
  case fullTextIndexed
  case failed
}

public enum PasteFailureReason: String, Codable, Equatable, Sendable {
  case recordMissing
  case blobMissing
  case fileUnavailable
  case formatUnsupported
  case pasteboardWriteFailed
  case accessibilityRevoked
  case targetAppFocusLost
  case pasteEventFailed
  case targetAppRejectedPaste
}
