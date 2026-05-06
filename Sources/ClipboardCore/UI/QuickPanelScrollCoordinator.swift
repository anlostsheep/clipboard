import Foundation

public enum QuickPanelScrollAnchor: Equatable, Sendable {
  case top
  case center
}

public struct QuickPanelScrollTarget: Equatable, Sendable {
  public let recordID: UUID
  public let anchor: QuickPanelScrollAnchor

  public init(recordID: UUID, anchor: QuickPanelScrollAnchor) {
    self.recordID = recordID
    self.anchor = anchor
  }
}

public struct QuickPanelScrollCoordinator: Sendable {
  public init() {}

  public mutating func targetAfterItemsChanged(
    itemIDs: [UUID],
    selectedIndex: Int
  ) -> QuickPanelScrollTarget? {
    Self.targetForItemsChange(itemIDs: itemIDs, selectedIndex: selectedIndex)
  }

  public static func targetForItemsChange(
    itemIDs: [UUID],
    selectedIndex: Int
  ) -> QuickPanelScrollTarget? {
    target(itemIDs: itemIDs, selectedIndex: selectedIndex, anchor: .top)
  }

  public static func targetForSelectionChange(
    itemIDs: [UUID],
    selectedIndex: Int
  ) -> QuickPanelScrollTarget? {
    target(itemIDs: itemIDs, selectedIndex: selectedIndex, anchor: .center)
  }

  private static func target(
    itemIDs: [UUID],
    selectedIndex: Int,
    anchor: QuickPanelScrollAnchor
  ) -> QuickPanelScrollTarget? {
    guard itemIDs.indices.contains(selectedIndex) else {
      return nil
    }

    return QuickPanelScrollTarget(recordID: itemIDs[selectedIndex], anchor: anchor)
  }
}
