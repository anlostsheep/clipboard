import Foundation

public extension ClipboardPayload {
  var plainTextForPaste: String? {
    switch self {
    case .text(let value):
      return value
    case .richText(let plainText, _, _):
      return plainText
    case .image, .fileURLs:
      return nil
    }
  }
}
