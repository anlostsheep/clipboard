import Foundation

public enum ClipboardIngestError: Error, Equatable {
  case unsupportedPayload
}

public struct ClipboardIngestService: Sendable {
  private let store: any HistoryStore
  private let privacyPolicy: PrivacyPolicy
  private let largeTextPolicy: LargeTextPolicy

  public init(store: any HistoryStore, privacyPolicy: PrivacyPolicy, largeTextPolicy: LargeTextPolicy) {
    self.store = store
    self.privacyPolicy = privacyPolicy
    self.largeTextPolicy = largeTextPolicy
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    guard let record = try makeRecord(from: capture) else { return nil }
    return try await store.upsert(record)
  }

  /// Builds the record without persisting it. Returns nil if PrivacyPolicy filters this capture.
  public func makeRecord(from capture: ClipboardCapture) throws -> ClipboardRecord? {
    try makeRecord(from: capture, applyingPrivacyPolicy: true)
  }

  public func makeRecord(
    from capture: ClipboardCapture,
    applyingPrivacyPolicy: Bool
  ) throws -> ClipboardRecord? {
    guard !applyingPrivacyPolicy || !privacyPolicy.shouldIgnore(
      pasteboardTypes: capture.pasteboardTypes,
      sourceBundleId: capture.sourceAppBundleId
    ) else {
      return nil
    }
    return try constructRecord(from: capture)
  }

  /// Persists an already-constructed record to the store.
  public func persist(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    try await store.upsert(record)
  }

  private func constructRecord(from capture: ClipboardCapture) throws -> ClipboardRecord {
    switch capture.payload {
    case let .text(text):
      return makeTextRecord(text: text, capture: capture, primaryType: primaryType(forText: text))
    case let .richText(plainText, rtfData, htmlData):
      return makeTextRecord(
        text: plainText,
        capture: capture,
        primaryType: .richText,
        contentHash: ClipboardContentHasher.hashRichText(
          plainText: plainText,
          rtfData: rtfData,
          htmlData: htmlData
        )
      )
    case let .image(data, _):
      return ClipboardRecord(
        id: UUID(),
        contentHash: ClipboardContentHasher.hashData(data),
        primaryType: .image,
        title: "Image \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))",
        plainTextPreview: nil,
        sourceAppBundleId: capture.sourceAppBundleId,
        sourceAppName: capture.sourceAppName,
        sourceDeviceHint: capture.isUniversalClipboard ? .universalClipboard : .local,
        createdAt: capture.capturedAt,
        lastCopiedAt: capture.capturedAt,
        copyCount: 1,
        isPinned: false,
        isFavorite: false,
        groupIds: [],
        retentionExempt: false,
        metadata: nil,
        pasteboardTypes: capture.pasteboardTypes
      )
    case let .fileURLs(urls):
      let joined = urls.map(\.absoluteString).joined(separator: "\n")
      return makeTextRecord(text: joined, capture: capture, primaryType: .file)
    }
  }

  private func makeTextRecord(
    text: String,
    capture: ClipboardCapture,
    primaryType: ClipboardContentType = .text,
    contentHash: String? = nil
  ) -> ClipboardRecord {
    let classification = largeTextPolicy.classify(text: text)
    let preview = classification.metadata?.previewExcerpt ?? String(text.prefix(2_048))
    let titleSource = preview.split(separator: "\n").first.map(String.init) ?? "Text"
    let title = String(titleSource.prefix(120))

    return ClipboardRecord(
      id: UUID(),
      contentHash: contentHash ?? ClipboardContentHasher.hashText(text),
      primaryType: primaryType,
      title: title.isEmpty ? "Text" : title,
      plainTextPreview: preview,
      sourceAppBundleId: capture.sourceAppBundleId,
      sourceAppName: capture.sourceAppName,
      sourceDeviceHint: capture.isUniversalClipboard ? .universalClipboard : .local,
      createdAt: capture.capturedAt,
      lastCopiedAt: capture.capturedAt,
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: classification.metadata,
      pasteboardTypes: capture.pasteboardTypes
    )
  }

  private func primaryType(forText text: String) -> ClipboardContentType {
    isHTTPURLText(text) ? .link : .text
  }

  private func isHTTPURLText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          !trimmed.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains),
          let components = URLComponents(string: trimmed),
          let scheme = components.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          components.host != nil else {
      return false
    }
    return true
  }

}
