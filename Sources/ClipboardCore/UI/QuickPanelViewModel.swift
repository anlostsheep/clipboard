import Foundation

public struct QuickPanelSelectionIntent: Equatable, Sendable {
  public let recordID: UUID
  public let autoPaste: Bool

  public init(recordID: UUID, autoPaste: Bool) {
    self.recordID = recordID
    self.autoPaste = autoPaste
  }
}

public struct QuickPanelSearchMatch: Equatable, Sendable {
  public let score: Int
  public let primaryTextOffsets: [Int]

  public init(score: Int, primaryTextOffsets: [Int]) {
    self.score = score
    self.primaryTextOffsets = primaryTextOffsets
  }
}

public actor QuickPanelViewModel {
  private let store: any HistoryStore
  private let pageLimit: Int
  private var refreshGeneration = 0
  public private(set) var items: [ClipboardRecord] = []
  public private(set) var selectedIndex: Int = 0
  public private(set) var searchMatches: [UUID: QuickPanelSearchMatch] = [:]

  public init(store: any HistoryStore, pageLimit: Int = 50) {
    self.store = store
    self.pageLimit = pageLimit
  }

  @discardableResult
  public func refresh(
    query: String,
    contentTypes: Set<ClipboardContentType> = [],
    groupIDs: Set<String> = [],
    sortOrder: HistorySortOrder = .lastCopied
  ) async -> Bool {
    refreshGeneration += 1
    let generation = refreshGeneration
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    // Type/group scoping still goes through HistoryQuery; text matching is
    // handled by FuzzyMatcher below because substring pre-filtering would
    // drop non-contiguous subsequence hits.
    let scopeQuery = HistoryQuery(text: "", contentTypes: contentTypes, groupIDs: groupIDs)
    let scoped = ((try? await store.fetchAll()) ?? []).filter { scopeQuery.matches($0) }

    let refreshedItems: [ClipboardRecord]
    var matches: [UUID: QuickPanelSearchMatch] = [:]
    if trimmedQuery.isEmpty {
      refreshedItems = scoped.sorted { Self.quickPanelSort($0, $1, sortOrder: sortOrder) }
    } else {
      let scored: [(record: ClipboardRecord, match: QuickPanelSearchMatch)] = scoped.compactMap { record in
        let primaryText = QuickPanelRowPresentation.primaryContentText(for: record)
        let primaryMatch = FuzzyMatcher.match(query: trimmedQuery, in: primaryText)
        let titleMatch = FuzzyMatcher.match(query: trimmedQuery, in: record.title)
        let sourceMatch = record.sourceAppName.flatMap {
          FuzzyMatcher.match(query: trimmedQuery, in: $0)
        }
        guard let best = [primaryMatch, titleMatch, sourceMatch].compactMap({ $0?.score }).max() else {
          return nil
        }
        return (
          record,
          QuickPanelSearchMatch(score: best, primaryTextOffsets: primaryMatch?.matchedOffsets ?? [])
        )
      }
      let ranked = scored.sorted { lhs, rhs in
        if lhs.record.isPinned != rhs.record.isPinned {
          return lhs.record.isPinned
        }
        if lhs.match.score != rhs.match.score {
          return lhs.match.score > rhs.match.score
        }
        if lhs.record.lastCopiedAt != rhs.record.lastCopiedAt {
          return lhs.record.lastCopiedAt > rhs.record.lastCopiedAt
        }
        return lhs.record.id.uuidString < rhs.record.id.uuidString
      }
      refreshedItems = ranked.map(\.record)
      for entry in ranked {
        matches[entry.record.id] = entry.match
      }
    }

    guard generation == refreshGeneration else {
      return false
    }

    items = QuickPanelListPolicy.limitedItems(refreshedItems, limit: pageLimit)
    searchMatches = matches
    selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
    return true
  }

  private static func quickPanelSort(
    _ lhs: ClipboardRecord,
    _ rhs: ClipboardRecord,
    sortOrder: HistorySortOrder
  ) -> Bool {
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
    switch sortOrder {
    case .lastCopied:
      if lhs.lastCopiedAt != rhs.lastCopiedAt {
        return lhs.lastCopiedAt > rhs.lastCopiedAt
      }
    case .firstCopied:
      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt > rhs.createdAt
      }
      if lhs.lastCopiedAt != rhs.lastCopiedAt {
        return lhs.lastCopiedAt > rhs.lastCopiedAt
      }
    case .copyCount:
      if lhs.copyCount != rhs.copyCount {
        return lhs.copyCount > rhs.copyCount
      }
      if lhs.lastCopiedAt != rhs.lastCopiedAt {
        return lhs.lastCopiedAt > rhs.lastCopiedAt
      }
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
