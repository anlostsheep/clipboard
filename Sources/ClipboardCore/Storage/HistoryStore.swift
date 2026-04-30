import Foundation

public protocol HistoryStore: Sendable {
  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func fetchAll() async -> [ClipboardRecord]
  func fetchPage(query: String, limit: Int) async -> [ClipboardRecord]
}

public actor InMemoryHistoryStore: HistoryStore {
  private var recordsByHash: [String: ClipboardRecord] = [:]

  public init() {}

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    if var existing = recordsByHash[record.contentHash] {
      existing.copyCount += 1
      existing.lastCopiedAt = record.lastCopiedAt
      recordsByHash[record.contentHash] = existing
      return existing
    }

    recordsByHash[record.contentHash] = record
    return record
  }

  public func fetchAll() async -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(query: String, limit: Int) async -> [ClipboardRecord] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let all = await fetchAll()
    let filtered = normalized.isEmpty ? all : all.filter { record in
      record.title.lowercased().contains(normalized) ||
        (record.plainTextPreview?.lowercased().contains(normalized) ?? false) ||
        (record.sourceAppName?.lowercased().contains(normalized) ?? false)
    }
    return Array(filtered.prefix(max(0, limit)))
  }
}
