import Foundation

public protocol PasteboardReading: AnyObject, Sendable {
  func currentChangeCount() async -> Int
  func readCurrentCapture() async -> ClipboardCapture?
}

public actor ClipboardMonitor {
  private let reader: PasteboardReading
  private var lastChangeCount: Int?
  private var isPaused = false

  public init(reader: PasteboardReading) {
    self.reader = reader
  }

  public func pause() { isPaused = true }
  public func resume() { isPaused = false }

  public func poll() async -> ClipboardCapture? {
    guard !isPaused else { return nil }

    let current = await reader.currentChangeCount()
    defer { lastChangeCount = current }

    guard lastChangeCount != current else {
      return nil
    }

    return await reader.readCurrentCapture()
  }
}
