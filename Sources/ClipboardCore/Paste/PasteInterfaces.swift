import Foundation

public protocol PasteboardWriting: AnyObject, Sendable {
  func write(payload: ClipboardPayload, marker: String) async -> Bool
  func containsMarker(_ marker: String) async -> Bool
}

public protocol PasteEventPosting: AnyObject, Sendable {
  func isAccessibilityTrusted() -> Bool
  func postCommandV() async -> Bool
}

public enum PasteTransactionState: Equatable, Sendable {
  case prepared
  case pasteboardWritten
  case pasteEventPosted
  case completed
  case failed(PasteFailureReason)
}

public struct PasteTransaction: Equatable, Sendable {
  public let id: UUID
  public let recordId: UUID
  public let startedAt: Date
  public var completedAt: Date?
  public var state: PasteTransactionState

  public init(id: UUID, recordId: UUID, startedAt: Date, completedAt: Date?, state: PasteTransactionState) {
    self.id = id
    self.recordId = recordId
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.state = state
  }
}
