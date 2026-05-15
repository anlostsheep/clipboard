import Foundation

public struct PasteController: Sendable {
  private let pasteboard: any PasteboardWriting
  private let eventPoster: any PasteEventPosting
  private let markerPrefix = "com.local.clipboard-manager.transaction"

  public init(pasteboard: any PasteboardWriting, eventPoster: any PasteEventPosting) {
    self.pasteboard = pasteboard
    self.eventPoster = eventPoster
  }

  public func paste(record: ClipboardRecord, payload: ClipboardPayload, autoPaste: Bool) async -> PasteTransaction {
    var transaction = PasteTransaction(
      id: UUID(),
      recordId: record.id,
      startedAt: Date(),
      completedAt: nil,
      state: .prepared
    )

    if autoPaste && !eventPoster.isAccessibilityTrusted() {
      return complete(&transaction, with: .failed(.accessibilityRevoked))
    }

    let marker = "\(markerPrefix).\(transaction.id.uuidString)"
    guard await pasteboard.write(payload: payload, marker: marker) else {
      return complete(&transaction, with: .failed(.pasteboardWriteFailed))
    }

    guard await pasteboard.containsMarker(marker) else {
      return complete(&transaction, with: .failed(.pasteboardWriteFailed))
    }

    transaction.state = .pasteboardWritten

    guard autoPaste else {
      return complete(&transaction, with: .completed)
    }

    let pasteEventResult = await eventPoster.postCommandV(marker: marker, pasteboard: pasteboard)
    guard pasteEventResult == .posted else {
      let failure: PasteFailureReason = switch pasteEventResult {
      case .posted:
        .pasteEventFailed
      case .postFailed:
        .pasteEventFailed
      case .targetAppFocusLost:
        .targetAppFocusLost
      case .targetAppRejectedPaste:
        .targetAppRejectedPaste
      }
      return complete(&transaction, with: .failed(failure))
    }

    transaction.state = .pasteEventPosted
    return complete(&transaction, with: .completed)
  }

  private func complete(_ transaction: inout PasteTransaction, with state: PasteTransactionState) -> PasteTransaction {
    transaction.state = state
    transaction.completedAt = Date()
    return transaction
  }
}
