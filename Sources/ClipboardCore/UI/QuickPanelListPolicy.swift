public enum QuickPanelListPolicy {
  public static let minimumHistoryItemsWhenAvailable = 5
  public static let visiblePinnedRowsWhenHistoryVisible = 2

  static func limitedItems(_ sortedItems: [ClipboardRecord], limit: Int) -> [ClipboardRecord] {
    let safeLimit = max(0, limit)
    guard safeLimit > 0 else {
      return []
    }

    let pinnedItems = sortedItems.filter(\.isPinned)
    let historyItems = sortedItems.filter { !$0.isPinned }
    guard !pinnedItems.isEmpty, !historyItems.isEmpty else {
      return Array(sortedItems.prefix(safeLimit))
    }

    let reservedHistoryCount = min(
      historyItems.count,
      Self.minimumHistoryItemsWhenAvailable,
      safeLimit
    )
    let pinnedLimit = max(0, safeLimit - reservedHistoryCount)
    let visiblePinnedItems = pinnedItems.prefix(pinnedLimit)
    let remainingHistorySlots = safeLimit - visiblePinnedItems.count

    return Array(visiblePinnedItems) + Array(historyItems.prefix(remainingHistorySlots))
  }
}
