import XCTest
@testable import ClipboardCore

final class ClipboardMonitorTests: XCTestCase {
  func testPollReturnsNilWhenChangeCountIsUnchanged() async {
    let reader = FakePasteboardReader(changeCount: 1, capture: nil)
    let monitor = ClipboardMonitor(reader: reader)

    _ = await monitor.poll()
    let second = await monitor.poll()

    XCTAssertNil(second)
  }

  func testPollReturnsCaptureWhenChangeCountChanges() async {
    let capture = ClipboardCapture(
      payload: .text("hello"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: nil,
      sourceAppName: nil,
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    let reader = FakePasteboardReader(changeCount: 1, capture: capture)
    let monitor = ClipboardMonitor(reader: reader)

    let first = await monitor.poll()

    XCTAssertEqual(first, capture)
  }
}

private final class FakePasteboardReader: PasteboardReading {
  let changeCount: Int
  let capture: ClipboardCapture?

  init(changeCount: Int, capture: ClipboardCapture?) {
    self.changeCount = changeCount
    self.capture = capture
  }

  func currentChangeCount() async -> Int {
    changeCount
  }

  func readCurrentCapture() async -> ClipboardCapture? {
    capture
  }
}
