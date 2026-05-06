import Foundation

public struct ClipboardCaptureCoordinator: Sendable {
  private let monitor: ClipboardMonitor
  private let ingestService: ClipboardIngestService
  private let payloadStore: any ClipboardPayloadStore

  public init(
    monitor: ClipboardMonitor,
    ingestService: ClipboardIngestService,
    payloadStore: any ClipboardPayloadStore
  ) {
    self.monitor = monitor
    self.ingestService = ingestService
    self.payloadStore = payloadStore
  }

  public func captureLatestChange() async throws -> ClipboardRecord? {
    guard let capture = await monitor.poll() else {
      return nil
    }

    return try await ingest(capture)
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    guard let record = try await ingestService.ingest(capture) else {
      return nil
    }

    await payloadStore.save(capture.payload, for: record.id)
    return record
  }
}
