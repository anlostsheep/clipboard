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
      pinnedAt: imported.isPinned ? imported.lastCopiedAt : nil,
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
      return ClipboardContentHasher.hashText(text)
    case let .richText(plainText, rtfData, htmlData):
      return ClipboardContentHasher.hashRichText(plainText: plainText, rtfData: rtfData, htmlData: htmlData)
    case let .image(data, _):
      return ClipboardContentHasher.hashData(data)
    case let .fileURLs(urls):
      let joinedURLs = urls.map(\.absoluteString).joined(separator: "\n")
      return ClipboardContentHasher.hashText(joinedURLs)
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
}
