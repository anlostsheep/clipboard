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

  public func refresh(query: String) async {
    refreshGeneration += 1
    let generation = refreshGeneration
    let refreshedItems = (try? await store.fetchPage(query: query, limit: pageLimit)) ?? []

    guard generation == refreshGeneration else {
      return
    }

    items = refreshedItems
    selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
  }

  public func moveSelection(delta: Int) {
    guard !items.isEmpty else {
      selectedIndex = 0
      return
    }

    selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
  }

  public func selectedIntent(autoPaste: Bool) -> QuickPanelSelectionIntent? {
    guard items.indices.contains(selectedIndex) else {
      return nil
    }

    return QuickPanelSelectionIntent(recordID: items[selectedIndex].id, autoPaste: autoPaste)
  }
}
