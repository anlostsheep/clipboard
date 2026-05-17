import CryptoKit
import Foundation

public struct ImportRecordBuilder: Sendable {
  public init() {}

  public func buildRecord(from imported: ImportedRecord, groupIDs: [String]) throws -> ClipboardRecord {
    ClipboardRecord(
      id: UUID(),
      contentHash: contentHash(for: imported.payload),
      primaryType: imported.primaryType,
      title: normalizedTitle(imported.title, fallback: imported.plainTextPreview, type: imported.primaryType),
      plainTextPreview: imported.plainTextPreview,
      sourceAppBundleId: imported.sourceAppBundleId,
      sourceAppName: imported.sourceAppName,
      sourceDeviceHint: imported.sourceDeviceHint,
      createdAt: imported.createdAt,
      lastCopiedAt: imported.lastCopiedAt,
      copyCount: imported.copyCount,
      isPinned: imported.isPinned,
      isFavorite: imported.isFavorite,
      groupIds: groupIDs,
      retentionExempt: imported.isPinned || imported.isFavorite,
      metadata: nil,
      pasteboardTypes: imported.pasteboardTypes
    )
  }

  public func contentHash(for payload: ClipboardPayload) -> String {
    switch payload {
    case let .text(text):
      return hash(Data(text.utf8))
    case let .richText(plainText, rtfData):
      var data = Data("richText\0".utf8)
      data.append(Data(plainText.utf8))
      data.append(0)
      data.append(rtfData)
      return hash(data)
    case let .image(data, _):
      return hash(data)
    case let .fileURLs(urls):
      let joinedURLs = urls.map(\.absoluteString).joined(separator: "\n")
      return hash(Data(joinedURLs.utf8))
    }
  }

  private func normalizedTitle(_ title: String, fallback: String?, type: ClipboardContentType) -> String {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedTitle.isEmpty {
      return String(trimmedTitle.prefix(120))
    }

    if let fallback {
      let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmedFallback.isEmpty {
        return String(trimmedFallback.prefix(120))
      }
    }

    switch type {
    case .text:
      return "Text"
    case .richText:
      return "Rich Text"
    case .link:
      return "Link"
    case .image:
      return "Image"
    case .file:
      return "Files"
    }
  }

  private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
