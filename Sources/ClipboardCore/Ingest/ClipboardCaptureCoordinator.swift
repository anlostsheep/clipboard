import Foundation

public protocol StorageFailureHandler: Sendable {
  /// Called when the underlying store throws StorageError.full / .fullAndCannotEvict.
  /// Returns true if the failure has been handled (e.g. monitor paused) — caller should NOT retry.
  /// Returns false to indicate the strategy is "continue evicting" — caller should attempt another upsert.
  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool

  /// Called after a successful persist. Used to clear failure state and send recovery notifications.
  func reportSuccess() async
}

public struct ClipboardCaptureCoordinator: Sendable {
  private let monitor: ClipboardMonitor
  private let ingestService: ClipboardIngestService
  private let payloadStore: any ClipboardPayloadStore
  private let failureHandler: any StorageFailureHandler
  private let captureControl: CaptureControlService?

  public init(
    monitor: ClipboardMonitor,
    ingestService: ClipboardIngestService,
    payloadStore: any ClipboardPayloadStore,
    failureHandler: any StorageFailureHandler,
    captureControl: CaptureControlService? = nil
  ) {
    self.monitor = monitor
    self.ingestService = ingestService
    self.payloadStore = payloadStore
    self.failureHandler = failureHandler
    self.captureControl = captureControl
  }

  public func captureLatestChange() async throws -> ClipboardRecord? {
    guard let capture = await monitor.poll() else { return nil }
    if let captureControl {
      switch await captureControl.evaluate(capture) {
      case .allow:
        return try await ingest(capture, applyingIngestPrivacyPolicy: false)
      case .skip:
        return nil
      }
    }
    return try await ingest(capture)
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    try await ingest(capture, applyingIngestPrivacyPolicy: true)
  }

  private func ingest(
    _ capture: ClipboardCapture,
    applyingIngestPrivacyPolicy: Bool
  ) async throws -> ClipboardRecord? {
    // Build the record first (privacy check + metadata) without touching the DB.
    guard let record = try ingestService.makeRecord(
      from: capture,
      applyingPrivacyPolicy: applyingIngestPrivacyPolicy
    ) else { return nil }

    // Persist payload to file system before writing to DB (spec §4 ordering).
    // If payload save fails, no DB row is ever written — no orphan records.
    try await payloadStore.save(capture.payload, for: record.id)

    var attempts = 0
    while true {
      do {
        let stored = try await ingestService.persist(record)
        await failureHandler.reportSuccess()
        return stored
      } catch let error as StorageError {
        attempts += 1
        let handled = await failureHandler.handleStorageFailure(error, record: record)
        if handled {
          // Handler took ownership (e.g. paused monitor); clean up the payload file.
          try? await payloadStore.delete(for: record.id)
          return nil
        }
        if attempts >= 10 {
          try? await payloadStore.delete(for: record.id)
          return nil  // safety guard against infinite loops
        }
      }
    }
  }
}
