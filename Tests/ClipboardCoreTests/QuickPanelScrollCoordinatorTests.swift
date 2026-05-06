import XCTest
@testable import ClipboardCore

final class QuickPanelScrollCoordinatorTests: XCTestCase {
  func testItemsChangeRequestsSelectedItemScrollEvenWhenSelectionIndexIsUnchanged() {
    var coordinator = QuickPanelScrollCoordinator()
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!

    let target = coordinator.targetAfterItemsChanged(itemIDs: [firstID, secondID], selectedIndex: 0)

    XCTAssertEqual(target, QuickPanelScrollTarget(recordID: firstID, anchor: .top))
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
}
