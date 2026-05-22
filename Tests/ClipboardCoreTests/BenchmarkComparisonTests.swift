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

  func testMetricComparisonExplainsMissingMaccyBaseline() {
    let comparison = BenchmarkComparison.compareMetric(
      name: "fetch_recent_50_ms",
      clipboardMedian: 10,
      clipboardP95: 15,
      maccyMedian: nil,
      maccyP95: nil,
      maccySource: nil
    )

    XCTAssertEqual(comparison.name, "fetch_recent_50_ms")
    XCTAssertEqual(comparison.result, .notComparable)
    XCTAssertEqual(comparison.confidence, .missingBaseline)
    XCTAssertEqual(comparison.reason, "Maccy baseline is missing for fetch_recent_50_ms")
  }

  func testMetricComparisonRecordsBetterSameWorseWithReasons() {
    let better = BenchmarkComparison.compareMetric(
      name: "fetch_recent_50_ms",
      clipboardMedian: 79,
      clipboardP95: 100,
      maccyMedian: 100,
      maccyP95: 100,
      maccySource: "same-machine-json"
    )
    let same = BenchmarkComparison.compareMetric(
      name: "search_http_50_ms",
      clipboardMedian: 90,
      clipboardP95: 151,
      maccyMedian: 100,
      maccyP95: 150,
      maccySource: "same-machine-json"
    )
    let worse = BenchmarkComparison.compareMetric(
      name: "store_load_ms",
      clipboardMedian: 121,
      clipboardP95: 130,
      maccyMedian: 100,
      maccyP95: 150,
      maccySource: "same-machine-json"
    )

    XCTAssertEqual(better.result, .better)
    XCTAssertEqual(better.confidence, .sameMachineBaseline)
    XCTAssertEqual(better.reason, "Clipboard median is at least 20% lower than Maccy and p95 is not worse")
    XCTAssertEqual(same.result, .same)
    XCTAssertEqual(same.reason, "Clipboard median is within the 20% same range or p95 prevents a better result")
    XCTAssertEqual(worse.result, .worse)
    XCTAssertEqual(worse.reason, "Clipboard median is more than 20% higher than Maccy")
  }
}
