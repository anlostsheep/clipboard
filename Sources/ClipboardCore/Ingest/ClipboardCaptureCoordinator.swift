import Foundation

public protocol StorageFailureHandler: Sendable {
  /// Called when the underlying store throws StorageError.full / .fullAndCannotEvict.
  /// Returns true if the failure has been handled (e.g. monitor paused) — caller should NOT retry.
  /// Returns false to indicate the strategy is "continue evicting" — caller should attempt another upsert.
  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool
}

public struct ClipboardCaptureCoordinator: Sendable {
  private let monitor: ClipboardMonitor
  private let ingestService: ClipboardIngestService
  private let payloadStore: any ClipboardPayloadStore
  private let failureHandler: any StorageFailureHandler

  public init(
    monitor: ClipboardMonitor,
    ingestService: ClipboardIngestService,
    payloadStore: any ClipboardPayloadStore,
    failureHandler: any StorageFailureHandler
  ) {
    self.monitor = monitor
    self.ingestService = ingestService
    self.payloadStore = payloadStore
    self.failureHandler = failureHandler
  }

  public func captureLatestChange() async throws -> ClipboardRecord? {
    guard let capture = await monitor.poll() else { return nil }
    return try await ingest(capture)
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    var attempts = 0
    while true {
      do {
        guard let record = try await ingestService.ingest(capture) else { return nil }
        try await payloadStore.save(capture.payload, for: record.id)
        return record
      } catch let error as StorageError {
        attempts += 1
        let placeholder = ClipboardRecord(
          id: UUID(),
          contentHash: "",
          primaryType: .text,
          title: "",
          plainTextPreview: nil,
          sourceAppBundleId: nil,
          sourceAppName: nil,
          sourceDeviceHint: .local,
          createdAt: capture.capturedAt,
          lastCopiedAt: capture.capturedAt,
          copyCount: 0,
          isPinned: false,
          isFavorite: false,
          groupIds: [],
          retentionExempt: false,
          metadata: nil,
          pasteboardTypes: capture.pasteboardTypes
        )
        let handled = await failureHandler.handleStorageFailure(error, record: placeholder)
        if handled { return nil }
        if attempts >= 10 { return nil }  // safety guard against infinite loops
      }
    }
  }
}
