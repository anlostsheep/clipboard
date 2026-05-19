import Foundation

public actor PayloadCleaningHistoryStore: ImportWritableHistoryStore, RetentionPolicyUpdating, HistoryMutationStore {
  private let underlying: any HistoryStore
  private let payloadStore: any ClipboardPayloadStore

  public init(underlying: any HistoryStore, payloadStore: any ClipboardPayloadStore) {
    self.underlying = underlying
    self.payloadStore = payloadStore
  }

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    let before = try await underlying.fetchAll()
    let result = try await underlying.upsert(record)
    try await deletePayloadsForRecordsRemoved(from: before)
    return result
  }

  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    guard let importing = underlying as? any ImportWritableHistoryStore else { return nil }
    return try await importing.record(forContentHash: hash)
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    let before = try await underlying.fetchAll()
    let result: ClipboardRecord
    if let importing = underlying as? any ImportWritableHistoryStore {
      result = try await importing.importRecord(record)
    } else {
      result = try await underlying.upsert(record)
    }
    try await deletePayloadsForRecordsRemoved(from: before)
    return result
  }

  public func fetchAll() async throws -> [ClipboardRecord] {
    try await underlying.fetchAll()
  }

  public func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord] {
    try await underlying.fetchPage(query, limit: limit)
  }

  public func count() async throws -> Int {
    try await underlying.count()
  }

  public func removeAll() async throws {
    let before = try await underlying.fetchAll()
    try await underlying.removeAll()
    for record in before {
      try await payloadStore.delete(for: record.id)
    }
  }

  public func deleteRecord(id: UUID) async throws -> ClipboardRecord? {
    guard let mutating = underlying as? any HistoryMutationStore else {
      return nil
    }
    let removed = try await mutating.deleteRecord(id: id)
    if let removed {
      try await payloadStore.delete(for: removed.id)
    }
    return removed
  }

  public func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    guard let mutating = underlying as? any HistoryMutationStore else {
      return try await importRecord(record)
    }
    return try await mutating.replaceRecord(record)
  }

  public func clearUnpinned() async throws -> [ClipboardRecord] {
    guard let mutating = underlying as? any HistoryMutationStore else {
      return []
    }
    let removed = try await mutating.clearUnpinned()
    for record in removed {
      try await payloadStore.delete(for: record.id)
    }
    return removed
  }

  public func evictOldest(percent: Double) async throws -> Int {
    let before = try await underlying.fetchAll()
    let removed = try await underlying.evictOldest(percent: percent)
    try await deletePayloadsForRecordsRemoved(from: before)
    return removed
  }

  public func updateRetentionPolicy(_ policy: RetentionPolicy) async throws {
    let before = try await underlying.fetchAll()
    guard let updating = underlying as? any RetentionPolicyUpdating else { return }
    try await updating.updateRetentionPolicy(policy)
    try await deletePayloadsForRecordsRemoved(from: before)
  }

  private func deletePayloadsForRecordsRemoved(from before: [ClipboardRecord]) async throws {
    let remainingIDs = Set(try await underlying.fetchAll().map(\.id))
    for record in before where !remainingIDs.contains(record.id) {
      try await payloadStore.delete(for: record.id)
    }
  }
}
