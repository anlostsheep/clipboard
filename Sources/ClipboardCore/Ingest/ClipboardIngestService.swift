import CryptoKit
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
    guard !privacyPolicy.shouldIgnore(
      pasteboardTypes: capture.pasteboardTypes,
      sourceBundleId: capture.sourceAppBundleId
    ) else {
      return nil
    }

    let record = try makeRecord(from: capture)
    return try await store.upsert(record)
  }

  private func makeRecord(from capture: ClipboardCapture) throws -> ClipboardRecord {
    switch capture.payload {
    case let .text(text):
      return makeTextRecord(text: text, capture: capture)
    case let .richText(plainText, _):
      return makeTextRecord(text: plainText, capture: capture, primaryType: .richText)
    case let .image(data, _):
      return ClipboardRecord(
        id: UUID(),
        contentHash: hashData(data),
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
    primaryType: ClipboardContentType = .text
  ) -> ClipboardRecord {
    let classification = largeTextPolicy.classify(text: text)
    let preview = classification.metadata?.previewExcerpt ?? String(text.prefix(2_048))
    let titleSource = preview.split(separator: "\n").first.map(String.init) ?? "Text"
    let title = String(titleSource.prefix(120))

    return ClipboardRecord(
      id: UUID(),
      contentHash: hashText(text),
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

  private func hashData(_ data: Data) -> String {
    digestHex(SHA256.hash(data: data))
  }

  private func hashText(_ text: String) -> String {
    var hasher = SHA256()
    let didHashContiguousStorage = text.utf8.withContiguousStorageIfAvailable { buffer in
      hasher.update(bufferPointer: UnsafeRawBufferPointer(buffer))
      return true
    } ?? false

    if !didHashContiguousStorage {
      var chunk: [UInt8] = []
      chunk.reserveCapacity(16 * 1024)

      for byte in text.utf8 {
        chunk.append(byte)
        if chunk.count == 16 * 1024 {
          hasher.update(data: chunk)
          chunk.removeAll(keepingCapacity: true)
        }
      }

      if !chunk.isEmpty {
        hasher.update(data: chunk)
      }
    }

    return digestHex(hasher.finalize())
  }

  private func digestHex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
