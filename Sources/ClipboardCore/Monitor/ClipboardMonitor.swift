import Foundation

public protocol PasteboardReading: AnyObject, Sendable {
  func currentChangeCount() async -> Int
  func readCurrentCapture() async -> ClipboardCapture?
}

public actor ClipboardMonitor {
  private let reader: PasteboardReading
  private var lastChangeCount: Int?

  public init(reader: PasteboardReading) {
    self.reader = reader
  }

  public func poll() async -> ClipboardCapture? {
    let current = await reader.currentChangeCount()
    defer { lastChangeCount = current }

    guard lastChangeCount != current else {
      return nil
    }

    return await reader.readCurrentCapture()
  }
}
