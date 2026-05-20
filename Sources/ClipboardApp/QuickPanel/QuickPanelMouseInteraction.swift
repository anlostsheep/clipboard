import Foundation

struct QuickPanelMouseInteraction {
  let selectItem: (Int) -> Void
  let submitSelection: () -> Void

  func handleMouseDown(rowIndex: Int, clickCount: Int) {
    handleClick(rowIndex: rowIndex, count: clickCount)
  }

  func handleClick(rowIndex: Int, count: Int) {
    switch count {
    case 1:
      selectItem(rowIndex)
    case 2:
      selectItem(rowIndex)
      submitSelection()
    default:
      break
    }
  }

  static func shortcutHint(
    returnCopiesOnly: Bool,
    actionPrompt: QuickPanelActionPrompt?
  ) -> String {
    if returnCopiesOnly {
      return "单击选择  Return/双击复制  Cmd+V 粘贴  Cmd+Q 退出  Esc 关闭"
    }

    if actionPrompt == .autoPasteRequiresAccessibilityPermission {
      return "单击选择  Return/双击需授权  Cmd+V 手动粘贴  Cmd+Q 退出"
    }

    return "单击选择  Return/双击自动粘贴  Cmd+Q 退出  Esc 关闭"
  }
}
