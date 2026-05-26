import Foundation

/// File-backed payload store. Each payload is serialized to a JSON envelope
/// and written as `<uuid>.<ext>` inside `payloadsDirectory`.
///
/// Write strategy: write to a `.tmp` sibling, then rename atomically to avoid
/// partial writes being visible to concurrent readers.
public actor SQLitePayloadStore: ClipboardPayloadStore {
  private let payloadsDirectory: URL

  public init(payloadsDirectory: URL) throws {
    self.payloadsDirectory = payloadsDirectory
    let fm = FileManager.default
    if !fm.fileExists(atPath: payloadsDirectory.path) {
      try fm.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)
    }
  }

  // MARK: - ClipboardPayloadStore

  public func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    let envelope = PayloadEnvelope(payload: payload)
    let url = fileURL(for: recordID, extension: envelope.fileExtension)
    let tmpURL = url.appendingPathExtension("tmp")
    let data = try envelope.encode()
    // Atomic write to temp file first
    try data.write(to: tmpURL, options: .atomic)
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) {
      _ = try fm.replaceItemAt(url, withItemAt: tmpURL, backupItemName: nil)
    } else {
      try fm.moveItem(at: tmpURL, to: url)
    }

    let prefix = recordID.uuidString
    let entries = (try? fm.contentsOfDirectory(atPath: payloadsDirectory.path)) ?? []
    for entry in entries
      where entry.hasPrefix(prefix) && !entry.hasSuffix(".tmp") && entry != url.lastPathComponent {
      try? fm.removeItem(at: payloadsDirectory.appendingPathComponent(entry))
    }
  }

  public func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    let fm = FileManager.default
    let candidates: [URL]
    do {
      candidates = try fm.contentsOfDirectory(
        at: payloadsDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey]
      )
      .filter { $0.lastPathComponent.hasPrefix(recordID.uuidString) && !$0.lastPathComponent.hasSuffix(".tmp") }
    } catch {
      return nil
    }
    guard let url = candidates.max(by: { lhs, rhs in
      let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      if lhsDate == rhsDate {
        return lhs.lastPathComponent < rhs.lastPathComponent
      }
      return lhsDate < rhsDate
    }) else { return nil }
    let data = try Data(contentsOf: url)
    return try PayloadEnvelope.decode(data, filename: url.lastPathComponent)
  }

  /// Removes all files whose name starts with `recordID.uuidString`. Idempotent.
  public func delete(for recordID: UUID) async throws {
    let fm = FileManager.default
    let prefix = recordID.uuidString
    guard let entries = try? fm.contentsOfDirectory(atPath: payloadsDirectory.path) else { return }
    for entry in entries where entry.hasPrefix(prefix) {
      try? fm.removeItem(at: payloadsDirectory.appendingPathComponent(entry))
    }
  }

  // MARK: - Orphan scanning helpers

  /// Returns the set of all non-tmp filenames currently on disk. Used by orphan scans.
  public func listAllFilenames() throws -> Set<String> {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: payloadsDirectory.path) else {
      return []
    }
    return Set(entries.filter { !$0.hasSuffix(".tmp") })
  }

  /// Deletes files whose names don't start with any of the given UUID string prefixes.
  /// Returns the count of removed files.
  @discardableResult
  public func removeOrphans(keepingPrefixes referenced: Set<String>) throws -> Int {
    let all = try listAllFilenames()
    let orphans = all.filter { name in
      !referenced.contains(where: { name.hasPrefix($0) })
    }
    let fm = FileManager.default
    var removed = 0
    for name in orphans {
      try? fm.removeItem(at: payloadsDirectory.appendingPathComponent(name))
      removed += 1
    }
    return removed
  }

  // MARK: - Private helpers

  private func fileURL(for recordID: UUID, extension ext: String) -> URL {
    payloadsDirectory.appendingPathComponent("\(recordID.uuidString).\(ext)")
  }
}

// MARK: - PayloadEnvelope

/// JSON envelope for a single ClipboardPayload, stored on disk.
/// All optional fields outside the active case are nil to keep files small.
private struct PayloadEnvelope: Codable {
  let kind: Kind
  let textPlain: String?
  let richTextPlain: String?
  let richTextRTF: Data?
  let richTextHTML: Data?
  let imageData: Data?
  let imageUTI: String?
  let fileURLStrings: [String]?

  enum Kind: String, Codable {
    case text
    case richText
    case image
    case fileURLs
  }

  init(payload: ClipboardPayload) {
    switch payload {
    case .text(let s):
      kind = .text
      textPlain = s
      richTextPlain = nil; richTextRTF = nil; richTextHTML = nil
      imageData = nil; imageUTI = nil
      fileURLStrings = nil

    case .richText(let plain, let rtf, let html):
      kind = .richText
      richTextPlain = plain; richTextRTF = rtf; richTextHTML = html
      textPlain = nil
      imageData = nil; imageUTI = nil
      fileURLStrings = nil

    case .image(let data, let uti):
      kind = .image
      imageData = data; imageUTI = uti
      textPlain = nil
      richTextPlain = nil; richTextRTF = nil; richTextHTML = nil
      fileURLStrings = nil

    case .fileURLs(let urls):
      kind = .fileURLs
      fileURLStrings = urls.map(\.absoluteString)
      textPlain = nil
      richTextPlain = nil; richTextRTF = nil; richTextHTML = nil
      imageData = nil; imageUTI = nil
    }
  }

  /// File extension to use when writing this envelope to disk.
  var fileExtension: String {
    switch kind {
    case .text:    return "txt"
    case .richText: return "richtext.json"
    case .image:
      switch imageUTI {
      case "public.jpeg": return "jpg"
      case "public.png":  return "png"
      case "public.tiff": return "tiff"
      default:            return "bin"
      }
    case .fileURLs: return "fileurls.json"
    }
  }

  func encode() throws -> Data {
    try JSONEncoder().encode(self)
  }

  static func decode(_ data: Data, filename: String) throws -> ClipboardPayload {
    let envelope = try JSONDecoder().decode(PayloadEnvelope.self, from: data)
    switch envelope.kind {
    case .text:
      return .text(envelope.textPlain ?? "")
    case .richText:
      return .richText(
        plainText: envelope.richTextPlain ?? "",
        rtfData: envelope.richTextRTF,
        htmlData: envelope.richTextHTML
      )
    case .image:
      return .image(
        data: envelope.imageData ?? Data(),
        uti: envelope.imageUTI ?? "public.data"
      )
    case .fileURLs:
      let urls = (envelope.fileURLStrings ?? []).compactMap(URL.init(string:))
      return .fileURLs(urls)
    }
  }
}
