import XCTest
@testable import ClipboardApp

final class QuickPanelLayoutMetricsTests: XCTestCase {
  func testPinnedSectionShowsOnlyTwoRowsWhenHistoryIsPresent() {
    XCTAssertEqual(
      QuickPanelLayoutMetrics.visiblePinnedRowCount(pinnedRowCount: 5, hasHistory: true),
      2
    )
  }

  func testPinnedSectionCanUseAllRowsWhenHistoryIsAbsent() {
    XCTAssertEqual(
      QuickPanelLayoutMetrics.visiblePinnedRowCount(pinnedRowCount: 5, hasHistory: false),
      5
    )
  }

  func testTopSectionRowsUseTopScrollAnchorToAvoidHeaderGap() {
    XCTAssertEqual(
      QuickPanelLayoutMetrics.sectionScrollAnchor(requested: .center, localRowIndex: 0),
      .top
    )
    XCTAssertEqual(
      QuickPanelLayoutMetrics.sectionScrollAnchor(requested: .center, localRowIndex: 1),
      .top
    )
  }

  func testLowerSectionRowsKeepRequestedScrollAnchor() {
    XCTAssertEqual(
      QuickPanelLayoutMetrics.sectionScrollAnchor(requested: .center, localRowIndex: 3),
      .center
    )
  }

  func testFlexibleSectionFramesUseTopAlignmentToAvoidVerticalGaps() {
    XCTAssertEqual(QuickPanelLayoutMetrics.sectionFrameAlignment, .topLeading)
  }
}
