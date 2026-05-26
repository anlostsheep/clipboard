import AppKit
import ClipboardCore

enum QuickPanelSectionFrameAlignment: Equatable {
  case topLeading
}

enum QuickPanelLayoutMetrics {
  static let panelSize = NSSize(width: 720, height: 560)
  static let compactRowMinHeight: CGFloat = 54
  static let rowInnerVerticalPadding: CGFloat = 5
  static let rowOuterVerticalPadding: CGFloat = 3
  static let rowDividerHeight: CGFloat = 1
  static let sectionFrameAlignment: QuickPanelSectionFrameAlignment = .topLeading

  static func visiblePinnedRowCount(pinnedRowCount: Int, hasHistory: Bool) -> Int {
    guard hasHistory else {
      return pinnedRowCount
    }

    return min(pinnedRowCount, QuickPanelListPolicy.visiblePinnedRowsWhenHistoryVisible)
  }

  static func pinnedSectionMaxHeight(pinnedRowCount: Int, hasHistory: Bool) -> CGFloat {
    let visibleRows = visiblePinnedRowCount(pinnedRowCount: pinnedRowCount, hasHistory: hasHistory)
    guard visibleRows > 0 else {
      return 0
    }

    let rowBlockHeight = compactRowMinHeight
      + rowInnerVerticalPadding * 2
      + rowOuterVerticalPadding * 2
      + rowDividerHeight
    return CGFloat(visibleRows) * rowBlockHeight
  }

  static func sectionScrollAnchor(
    requested: QuickPanelScrollAnchor,
    localRowIndex: Int
  ) -> QuickPanelScrollAnchor {
    guard requested == .center, localRowIndex <= 1 else {
      return requested
    }

    return .top
  }
}
