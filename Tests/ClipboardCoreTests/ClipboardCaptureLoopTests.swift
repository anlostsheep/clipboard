import XCTest
@testable import ClipboardCore

final class ClipboardCaptureLoopTests: XCTestCase {
  func testCaptureLoopRepeatsUntilStopped() async throws {
    let reachedSecondCapture = expectation(description: "loop captured twice")
    let spy = CaptureLoopSpy(targetCount: 2, expectation: reachedSecondCapture)
    let loop = ClipboardCaptureLoop(
      intervalNanoseconds: 1,
      capture: {
        await spy.capture()
      },
      sleep: { _ in
        await Task.yield()
      }
    )

    await loop.start()
    await fulfillment(of: [reachedSecondCapture], timeout: 1)
    await loop.stop()
    let stoppedCount = await spy.currentCount()
    try await Task.sleep(nanoseconds: 10_000_000)
    let finalCount = await spy.currentCount()

    XCTAssertGreaterThanOrEqual(stoppedCount, 2)
    XCTAssertEqual(finalCount, stoppedCount)
    let isRunning = await loop.isRunning
    XCTAssertFalse(isRunning)
  }
}

private actor CaptureLoopSpy {
  private let targetCount: Int
  private let expectation: XCTestExpectation
  private var didFulfill = false
  private(set) var count = 0

  init(targetCount: Int, expectation: XCTestExpectation) {
    self.targetCount = targetCount
    self.expectation = expectation
  }

  func capture() {
    count += 1
    if count >= targetCount && !didFulfill {
      didFulfill = true
      expectation.fulfill()
    }
  }

  func currentCount() -> Int {
    count
  }
}
