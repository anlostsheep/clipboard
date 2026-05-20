import XCTest
@testable import ClipboardApp

final class QuickPanelMouseInteractionTests: XCTestCase {
  func testSingleClickSelectsRowWithoutSubmitting() {
    var selectedIndexes: [Int] = []
    var submitCount = 0
    let interaction = QuickPanelMouseInteraction(
      selectItem: { selectedIndexes.append($0) },
      submitSelection: { submitCount += 1 }
    )

    interaction.handleClick(rowIndex: 2, count: 1)

    XCTAssertEqual(selectedIndexes, [2])
    XCTAssertEqual(submitCount, 0)
  }

  func testDoubleClickSelectsRowThenSubmits() {
    var events: [String] = []
    let interaction = QuickPanelMouseInteraction(
      selectItem: { events.append("select:\($0)") },
      submitSelection: { events.append("submit") }
    )

    interaction.handleClick(rowIndex: 3, count: 2)

    XCTAssertEqual(events, ["select:3", "submit"])
  }

  func testShortcutHintDescribesSingleClickSelectionAndDoubleClickCopyOnlyExecution() {
    let hint = QuickPanelMouseInteraction.shortcutHint(
      returnCopiesOnly: true,
      actionPrompt: nil
    )

    XCTAssertEqual(hint, "单击选择  Return/双击复制  Cmd+V 粘贴  Esc 关闭")
  }

  func testShortcutHintDescribesSingleClickSelectionAndDoubleClickAutoPasteExecution() {
    let hint = QuickPanelMouseInteraction.shortcutHint(
      returnCopiesOnly: false,
      actionPrompt: nil
    )

    XCTAssertEqual(hint, "单击选择  Return/双击自动粘贴  Esc 关闭")
  }

  func testShortcutHintDescribesDoubleClickAuthorizationState() {
    let hint = QuickPanelMouseInteraction.shortcutHint(
      returnCopiesOnly: false,
      actionPrompt: .autoPasteRequiresAccessibilityPermission
    )

    XCTAssertEqual(hint, "单击选择  Return/双击需授权  Cmd+V 手动粘贴")
  }
}
