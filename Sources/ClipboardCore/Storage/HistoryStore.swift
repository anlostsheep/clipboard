import Foundation

public enum StorageError: Error, Equatable {
  case full
  case fullAndCannotEvict
  case underlying(String)
}

public struct HistoryQuery: Equatable, Sendable {
  public var text: String
  public var contentTypes: Set<ClipboardContentType>
  public var groupIDs: Set<String>

  public init(
    text: String = "",
    contentTypes: Set<ClipboardContentType> = [],
    groupIDs: Set<String> = []
  ) {
    self.text = text
    self.contentTypes = contentTypes
    self.groupIDs = groupIDs
  }

  var normalizedText: String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  func matches(_ record: ClipboardRecord) -> Bool {
    let textMatches = normalizedText.isEmpty ||
      record.title.lowercased().contains(normalizedText) ||
      (record.plainTextPreview?.lowercased().contains(normalizedText) ?? false) ||
      (record.sourceAppName?.lowercased().contains(normalizedText) ?? false)

    let typeMatches = contentTypes.isEmpty || contentTypes.contains(record.primaryType)
    let groupMatches = groupIDs.isEmpty || !Set(record.groupIds).isDisjoint(with: groupIDs)

    return textMatches && typeMatches && groupMatches
  }
}

public protocol HistoryStore: Sendable {
  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func fetchAll() async throws -> [ClipboardRecord]
  func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord]
  func count() async throws -> Int
  func removeAll() async throws
  /// Removes the oldest ceil(N × percent) non-exempt records
  /// (isPinned=false AND isFavorite=false AND retentionExempt=false).
  /// Returns the actual number of records removed; returns 0 if no candidates exist or percent <= 0.
  func evictOldest(percent: Double) async throws -> Int
}

public protocol ImportWritableHistoryStore: HistoryStore {
  func record(forContentHash hash: String) async throws -> ClipboardRecord?
  func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord
}

public protocol HistoryMutationStore: HistoryStore {
  func deleteRecord(id: UUID) async throws -> ClipboardRecord?
  func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func clearUnpinned() async throws -> [ClipboardRecord]
}

public protocol RetentionPolicyUpdating: Sendable {
  func updateRetentionPolicy(_ policy: RetentionPolicy) async throws
}

public extension HistoryStore {
  func fetchPage(query text: String, limit: Int) async throws -> [ClipboardRecord] {
    try await fetchPage(HistoryQuery(text: text), limit: limit)
  }
}

public actor InMemoryHistoryStore: ImportWritableHistoryStore, HistoryMutationStore {
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

  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    recordsByHash[hash]
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    recordsByHash[record.contentHash] = record
    return record
  }

  public func fetchAll() async throws -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord] {
    let all = try await fetchAll()
    let filtered = all.filter { query.matches($0) }
    return Array(filtered.prefix(max(0, limit)))
  }

  public func count() async throws -> Int {
    recordsByHash.count
  }

  public func removeAll() async throws {
    recordsByHash.removeAll()
  }

  public func deleteRecord(id: UUID) async throws -> ClipboardRecord? {
    guard let record = recordsByHash.values.first(where: { $0.id == id }) else {
      return nil
    }
    recordsByHash.removeValue(forKey: record.contentHash)
    return record
  }

  public func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    guard let existing = recordsByHash.values.first(where: { $0.id == record.id }) else {
      throw HistoryMutationError.recordNotFound
    }
    recordsByHash.removeValue(forKey: existing.contentHash)
    recordsByHash[record.contentHash] = record
    return record
  }

  public func clearUnpinned() async throws -> [ClipboardRecord] {
    let removed = recordsByHash.values.filter { !$0.isPinned }
    for record in removed {
      recordsByHash.removeValue(forKey: record.contentHash)
    }
    return removed.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
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
  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws
  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload?
  /// Removes the payload for the given record. Idempotent: succeeds silently if no entry exists.
  func delete(for recordID: UUID) async throws
}

public actor InMemoryPayloadStore: ClipboardPayloadStore {
  private var payloadsByRecordID: [UUID: ClipboardPayload] = [:]

  public init() {}

  public func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    payloadsByRecordID[recordID] = payload
  }

  public func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    payloadsByRecordID[recordID]
  }

  public func delete(for recordID: UUID) async throws {
    payloadsByRecordID.removeValue(forKey: recordID)
  }
}
