import Foundation

public enum StorageError: Error, Equatable {
  case full
  case fullAndCannotEvict
  case underlying(String)
}

public protocol HistoryStore: Sendable {
  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func fetchAll() async throws -> [ClipboardRecord]
  func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord]
  func count() async throws -> Int
  func removeAll() async throws
  /// Removes the oldest ceil(N × percent) non-exempt records
  /// (isPinned=false AND isFavorite=false AND retentionExempt=false).
  /// Returns the actual number of records removed; returns 0 if no candidates exist or percent <= 0.
  func evictOldest(percent: Double) async throws -> Int
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

  public func fetchAll() async throws -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let all = try await fetchAll()
    let filtered = normalized.isEmpty ? all : all.filter { record in
      record.title.lowercased().contains(normalized) ||
        (record.plainTextPreview?.lowercased().contains(normalized) ?? false) ||
        (record.sourceAppName?.lowercased().contains(normalized) ?? false)
    }
    return Array(filtered.prefix(max(0, limit)))
  }

  public func count() async throws -> Int {
    recordsByHash.count
  }

  public func removeAll() async throws {
    recordsByHash.removeAll()
  }

  public func evictOldest(percent: Double) async throws -> Int {
    let candidates = recordsByHash.values
      .filter { !$0.isPinned && !$0.isFavorite && !$0.retentionExempt }
      .sorted { $0.lastCopiedAt < $1.lastCopiedAt }
    guard !candidates.isEmpty else { return 0 }
    let target = Int((Double(candidates.count) * percent).rounded(.up))
    guard target > 0 else { return 0 }
    let toRemove = candidates.prefix(target)
    for record in toRemove {
      recordsByHash.removeValue(forKey: record.contentHash)
    }
    return toRemove.count
  }
}

public protocol ClipboardPayloadStore: Sendable {
  func save(_ payload: ClipboardPayload, for recordID: UUID) async
  func loadPayload(for recordID: UUID) async -> ClipboardPayload?
}

public actor InMemoryPayloadStore: ClipboardPayloadStore {
  private var payloadsByRecordID: [UUID: ClipboardPayload] = [:]

  public init() {}

  public func save(_ payload: ClipboardPayload, for recordID: UUID) async {
    payloadsByRecordID[recordID] = payload
  }

  public func loadPayload(for recordID: UUID) async -> ClipboardPayload? {
    payloadsByRecordID[recordID]
  }
}
