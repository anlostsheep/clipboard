import Foundation

public enum QuickPanelScrollAnchor: Equatable, Sendable {
  case top
  case center
}

public enum QuickPanelScrollAnimation: Equatable, Sendable {
  case immediate
  case animated
}

public struct QuickPanelScrollTarget: Equatable, Sendable {
  public let recordID: UUID
  public let anchor: QuickPanelScrollAnchor
  public let animation: QuickPanelScrollAnimation

  public init(
    recordID: UUID,
    anchor: QuickPanelScrollAnchor,
    animation: QuickPanelScrollAnimation = .animated
  ) {
    self.recordID = recordID
    self.anchor = anchor
    self.animation = animation
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
    target(itemIDs: itemIDs, selectedIndex: selectedIndex, anchor: .center, animation: .immediate)
  }

  public static func targetForSelectionChange(
    itemIDs: [UUID],
    selectedIndex: Int
  ) -> QuickPanelScrollTarget? {
    target(itemIDs: itemIDs, selectedIndex: selectedIndex, anchor: .center, animation: .animated)
  }

  private static func target(
    itemIDs: [UUID],
    selectedIndex: Int,
    anchor: QuickPanelScrollAnchor,
    animation: QuickPanelScrollAnimation
  ) -> QuickPanelScrollTarget? {
    guard itemIDs.indices.contains(selectedIndex) else {
      return nil
    }

    return QuickPanelScrollTarget(recordID: itemIDs[selectedIndex], anchor: anchor, animation: animation)
  }
}
