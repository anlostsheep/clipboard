import Foundation

/// Decorator that watches for `StorageError.full` from the underlying store and
/// triggers `evictOldest` to free space, retrying up to `maxRounds` times.
/// Decouples self-healing logic from the SQLite implementation for testability
/// and allows wrapping any conforming `HistoryStore`.
public actor SelfHealingHistoryStore: ImportWritableHistoryStore, RetentionPolicyUpdating {
  private let underlying: any HistoryStore
  private let maxRounds: Int
  private let evictPercent: Double

  public init(underlying: any HistoryStore, maxRounds: Int = 3, evictPercent: Double = 0.10) {
    self.underlying = underlying
    self.maxRounds = maxRounds
    self.evictPercent = evictPercent
  }

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    var attempt = 0
    while true {
      do {
        return try await underlying.upsert(record)
      } catch StorageError.full {
        guard attempt < maxRounds else { throw StorageError.full }
        let removed = try await underlying.evictOldest(percent: evictPercent)
        if removed == 0 {
          throw StorageError.fullAndCannotEvict
        }
        attempt += 1
      }
    }
  }

  public func record(forContentHash hash: String) async throws -> ClipboardRecord? {
    guard let importing = underlying as? any ImportWritableHistoryStore else { return nil }
    return try await importing.record(forContentHash: hash)
  }

  public func importRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    guard let importing = underlying as? any ImportWritableHistoryStore else {
      return try await upsert(record)
    }

    var attempt = 0
    while true {
      do {
        return try await importing.importRecord(record)
      } catch StorageError.full {
        guard attempt < maxRounds else { throw StorageError.full }
        let removed = try await underlying.evictOldest(percent: evictPercent)
        if removed == 0 {
          throw StorageError.fullAndCannotEvict
        }
        attempt += 1
      }
    }
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
    try await underlying.removeAll()
  }

  public func evictOldest(percent: Double) async throws -> Int {
    try await underlying.evictOldest(percent: percent)
  }

  public func updateRetentionPolicy(_ policy: RetentionPolicy) async throws {
    guard let updating = underlying as? any RetentionPolicyUpdating else { return }
    try await updating.updateRetentionPolicy(policy)
  }
}
