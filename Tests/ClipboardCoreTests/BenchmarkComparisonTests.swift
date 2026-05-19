import XCTest
@testable import ClipboardCore

final class BenchmarkComparisonTests: XCTestCase {
  func testBetterWhenClipboardMedianTwentyPercentLowerAndP95NotWorse() {
    let result = BenchmarkComparison.classify(
      clipboardMedian: 79,
      maccyMedian: 100,
      clipboardP95: 150,
      maccyP95: 150
    )

    XCTAssertEqual(result, .better)
  }

  func testSameWhenMedianWithinTwentyPercent() {
    let result = BenchmarkComparison.classify(
      clipboardMedian: 90,
      maccyMedian: 100,
      clipboardP95: 180,
      maccyP95: 150
    )

    XCTAssertEqual(result, .same)
  }

  func testSameAtExactThresholds() {
    XCTAssertEqual(
      BenchmarkComparison.classify(
        clipboardMedian: 80,
        maccyMedian: 100,
        clipboardP95: 100,
        maccyP95: 100
      ),
      .same
    )

    XCTAssertEqual(
      BenchmarkComparison.classify(
        clipboardMedian: 120,
        maccyMedian: 100,
        clipboardP95: 100,
        maccyP95: 100
      ),
      .same
    )
  }

  func testSameWhenMedianIsBetterButP95IsWorse() {
    let result = BenchmarkComparison.classify(
      clipboardMedian: 79,
      maccyMedian: 100,
      clipboardP95: 151,
      maccyP95: 150
    )

    XCTAssertEqual(result, .same)
  }

  func testWorseWhenClipboardMedianTwentyPercentHigher() {
    let result = BenchmarkComparison.classify(
      clipboardMedian: 121,
      maccyMedian: 100,
      clipboardP95: 120,
      maccyP95: 150
    )

    XCTAssertEqual(result, .worse)
  }

  func testNotComparableWhenMaccyMetricIsMissing() {
    XCTAssertEqual(
      BenchmarkComparison.classify(
        clipboardMedian: 79,
        maccyMedian: nil,
        clipboardP95: 150,
        maccyP95: 150
      ),
      .notComparable
    )

    XCTAssertEqual(
      BenchmarkComparison.classify(
        clipboardMedian: 79,
        maccyMedian: 100,
        clipboardP95: 150,
        maccyP95: nil
      ),
      .notComparable
    )
  }

  func testNotComparableWhenMaccyMedianIsZeroOrNegative() {
    XCTAssertEqual(
      BenchmarkComparison.classify(
        clipboardMedian: 79,
        maccyMedian: 0,
        clipboardP95: 150,
        maccyP95: 150
      ),
      .notComparable
    )

    XCTAssertEqual(
      BenchmarkComparison.classify(
        clipboardMedian: 79,
        maccyMedian: -1,
        clipboardP95: 150,
        maccyP95: 150
      ),
      .notComparable
    )
  }
}
