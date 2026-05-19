import XCTest
@testable import ClipboardCore

final class QuickPanelScrollCoordinatorTests: XCTestCase {
  func testItemsChangeCentersSelectedItemToAvoidClippingAfterDeletion() {
    var coordinator = QuickPanelScrollCoordinator()
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!

    let target = coordinator.targetAfterItemsChanged(itemIDs: [firstID, secondID], selectedIndex: 0)

    XCTAssertEqual(target, QuickPanelScrollTarget(recordID: firstID, anchor: .center, animation: .immediate))
  }

  func testItemsChangeScrollsImmediatelyToAvoidListMutationAnimationOverlap() {
    var coordinator = QuickPanelScrollCoordinator()
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000035")!

    let target = coordinator.targetAfterItemsChanged(itemIDs: [firstID], selectedIndex: 0)

    XCTAssertEqual(target?.animation, .immediate)
  }

  func testSelectionChangeRequestsCenteredSelectedItemScroll() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000033")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000034")!
    let target = QuickPanelScrollCoordinator.targetForSelectionChange(
      itemIDs: [firstID, secondID],
      selectedIndex: 1
    )

    XCTAssertEqual(target, QuickPanelScrollTarget(recordID: secondID, anchor: .center))
  }

  func testSelectionChangeCanAnimateToKeepKeyboardNavigationLegible() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000036")!

    let target = QuickPanelScrollCoordinator.targetForSelectionChange(itemIDs: [firstID], selectedIndex: 0)

    XCTAssertEqual(target?.animation, .animated)
  }
}
