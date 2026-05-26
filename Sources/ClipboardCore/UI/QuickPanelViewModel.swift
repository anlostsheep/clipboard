import Foundation

public struct QuickPanelSelectionIntent: Equatable, Sendable {
  public let recordID: UUID
  public let autoPaste: Bool

  public init(recordID: UUID, autoPaste: Bool) {
    self.recordID = recordID
    self.autoPaste = autoPaste
  }
}

public actor QuickPanelViewModel {
  private let store: any HistoryStore
  private let pageLimit: Int
  private var refreshGeneration = 0
  public private(set) var items: [ClipboardRecord] = []
  public private(set) var selectedIndex: Int = 0

  public init(store: any HistoryStore, pageLimit: Int = 50) {
    self.store = store
    self.pageLimit = pageLimit
  }

  @discardableResult
  public func refresh(
    query: String,
    contentTypes: Set<ClipboardContentType> = [],
    groupIDs: Set<String> = []
  ) async -> Bool {
    refreshGeneration += 1
    let generation = refreshGeneration
    let historyQuery = HistoryQuery(text: query, contentTypes: contentTypes, groupIDs: groupIDs)
    let refreshedItems = ((try? await store.fetchAll()) ?? [])
      .filter { historyQuery.matches($0) }
      .sorted(by: Self.quickPanelSort)

    guard generation == refreshGeneration else {
      return false
    }

    items = QuickPanelListPolicy.limitedItems(refreshedItems, limit: pageLimit)
    selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
    return true
  }

  private static func quickPanelSort(_ lhs: ClipboardRecord, _ rhs: ClipboardRecord) -> Bool {
    if lhs.isPinned != rhs.isPinned {
      return lhs.isPinned && !rhs.isPinned
    }
    if lhs.isPinned && rhs.isPinned {
      let lhsPinnedAt = lhs.pinnedAt ?? lhs.lastCopiedAt
      let rhsPinnedAt = rhs.pinnedAt ?? rhs.lastCopiedAt
      if lhsPinnedAt != rhsPinnedAt {
        return lhsPinnedAt > rhsPinnedAt
      }
    }
    if lhs.lastCopiedAt != rhs.lastCopiedAt {
      return lhs.lastCopiedAt > rhs.lastCopiedAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }

  public func moveSelection(delta: Int) {
    guard !items.isEmpty else {
      selectedIndex = 0
      return
    }

    selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
  }

  public func setSelection(index: Int) {
    guard items.indices.contains(index) else {
      return
    }
    selectedIndex = index
  }

  public func selectedIntent(autoPaste: Bool) -> QuickPanelSelectionIntent? {
    guard items.indices.contains(selectedIndex) else {
      return nil
    }

    return QuickPanelSelectionIntent(recordID: items[selectedIndex].id, autoPaste: autoPaste)
  }
}
