import Foundation
import SQLite3
import os.log

/// Configures how many records the store will retain before evicting old entries.
public struct RetentionPolicy: Sendable {
  public let maxCount: Int
  public let maxAgeDays: Int

  public init(maxCount: Int = 5000, maxAgeDays: Int = 180) {
    self.maxCount = maxCount
    self.maxAgeDays = maxAgeDays
  }
}

public actor SQLiteHistoryStore: HistoryStore, RetentionPolicyUpdating {
  private let connection: SQLiteConnection
  private var retentionPolicy: RetentionPolicy
  private var indexByHash: [String: ClipboardRecord] = [:]
  /// True while upsert holds an explicit BEGIN IMMEDIATE transaction, so that
  /// deleteRecords called from enforceRetention can reuse the outer transaction.
  private var inExplicitTransaction = false
  private static let logger = Logger(subsystem: "clipboard.storage", category: "SQLiteHistoryStore")

  public init(
    databaseFile: URL,
    retentionPolicy: RetentionPolicy = RetentionPolicy()
  ) throws {
    let dir = databaseFile.deletingLastPathComponent()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path) {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    let conn: SQLiteConnection
    do {
      conn = try SQLiteConnection(path: databaseFile.path)
      // Run a quick integrity check before trusting the database.
      // sqlite3_open_v2 succeeds even for garbage files; PRAGMA quick_check
      // detects structural corruption by reading the B-tree pages.
      let stmt = try conn.prepare("PRAGMA quick_check")
      defer { stmt.finalize() }
      _ = try stmt.step()
      let status = stmt.columnText(0) ?? ""
      if status != "ok" {
        throw StorageError.underlying("integrity check failed: \(status)")
      }
    } catch let error as StorageError {
      if case .underlying = error, fm.fileExists(atPath: databaseFile.path) {
        let backup = try SQLiteSchema.backupCorruptedDatabase(at: databaseFile)
        Self.logger.error("backed up corrupted DB to \(backup.path)")
      }
      throw error
    }
    self.connection = conn
    self.retentionPolicy = retentionPolicy
    try SQLiteSchema.setupPragmas(connection: connection)
    try SQLiteSchema.migrate(connection: connection)
    self.indexByHash = try Self.loadInitialIndex(connection: connection)
  }

  /// Clears the in-memory index. Does not close the underlying connection.
  public func close() {
    indexByHash.removeAll()
  }

  /// Returns all valid record UUIDs as a Set of strings for SQLitePayloadStore.removeOrphans prefix matching.
  public func referencedPayloadFilenamePrefixes() async -> Set<String> {
    Set(indexByHash.values.map { $0.id.uuidString })
  }

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    // Wrap writeRecord + enforceRetention in a single transaction so that a crash
    // between the two operations cannot leave DB in a partially-retained state (spec §4).
    try connection.exec("BEGIN IMMEDIATE")
    inExplicitTransaction = true
    defer { inExplicitTransaction = false }

    do {
      let result: ClipboardRecord
      if let existing = indexByHash[record.contentHash] {
        var updated = existing
        updated.copyCount += 1
        updated.lastCopiedAt = record.lastCopiedAt
        try writeRecord(updated)
        indexByHash[updated.contentHash] = updated
        result = updated
      } else {
        try writeRecord(record)
        indexByHash[record.contentHash] = record
        result = record
      }
      try enforceRetention()  // runs inside the same transaction via inExplicitTransaction flag
      try connection.exec("COMMIT")
      return result
    } catch {
      try? connection.exec("ROLLBACK")
      throw error
    }
  }

  public func fetchAll() async throws -> [ClipboardRecord] {
    indexByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(_ query: HistoryQuery, limit: Int) async throws -> [ClipboardRecord] {
    let all = try await fetchAll()
    let filtered = all.filter { query.matches($0) }
    return Array(filtered.prefix(max(0, limit)))
  }

  public func count() async throws -> Int {
    indexByHash.count
  }

  public func removeAll() async throws {
    try connection.exec("DELETE FROM records")
    indexByHash.removeAll()
  }

  /// Removes the oldest `percent` fraction of non-exempt records.
  /// Returns the number of records actually removed.
  public func evictOldest(percent: Double) async throws -> Int {
    let candidates = indexByHash.values
      .filter { !$0.isPinned && !$0.isFavorite && !$0.retentionExempt }
      .sorted { $0.lastCopiedAt < $1.lastCopiedAt }
    guard !candidates.isEmpty else { return 0 }
    let target = Int((Double(candidates.count) * percent).rounded(.up))
    guard target > 0 else { return 0 }
    let toRemove = Array(candidates.prefix(target))
    try deleteRecords(ids: toRemove.map(\.id))
    for record in toRemove {
      indexByHash.removeValue(forKey: record.contentHash)
    }
    try connection.exec("PRAGMA incremental_vacuum")
    return toRemove.count
  }

  public func updateRetentionPolicy(_ policy: RetentionPolicy) async throws {
    retentionPolicy = policy
    try enforceRetention()
  }

  // MARK: - Internal

  private func writeRecord(_ r: ClipboardRecord) throws {
    let sql = """
      INSERT INTO records (
        id, content_hash, primary_type, title, plain_preview,
        source_bundle, source_app, source_device,
        created_at, last_copied_at, copy_count,
        is_pinned, is_favorite, group_ids_json, retention_exempt,
        metadata_json, pasteboard_types_json, payload_ref
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(content_hash) DO UPDATE SET
        copy_count = copy_count + 1,
        last_copied_at = excluded.last_copied_at
    """
    let stmt = try connection.prepare(sql)
    defer { stmt.finalize() }
    stmt.bindText(1, r.id.uuidString)
    stmt.bindText(2, r.contentHash)
    stmt.bindText(3, r.primaryType.rawValue)
    stmt.bindText(4, r.title)
    stmt.bindText(5, r.plainTextPreview)
    stmt.bindText(6, r.sourceAppBundleId)
    stmt.bindText(7, r.sourceAppName)
    stmt.bindText(8, r.sourceDeviceHint.rawValue)
    stmt.bindDouble(9, r.createdAt.timeIntervalSince1970)
    stmt.bindDouble(10, r.lastCopiedAt.timeIntervalSince1970)
    stmt.bindInt(11, r.copyCount)
    stmt.bindBool(12, r.isPinned)
    stmt.bindBool(13, r.isFavorite)
    stmt.bindText(14, try Self.encodeJSON(r.groupIds))
    stmt.bindBool(15, r.retentionExempt)
    stmt.bindText(16, try Self.encodeJSONOptional(r.metadata))
    stmt.bindText(17, try Self.encodeJSON(Array(r.pasteboardTypes)))
    stmt.bindText(18, nil)  // payload_ref handled separately by PayloadStore
    _ = try stmt.step()
  }

  /// Deletes records by UUID.
  /// When called from within an existing transaction (inExplicitTransaction == true), reuses
  /// the outer transaction. Otherwise wraps the deletes in its own BEGIN IMMEDIATE/COMMIT.
  private func deleteRecords(ids: [UUID]) throws {
    guard !ids.isEmpty else { return }
    let needsOwnTransaction = !inExplicitTransaction
    if needsOwnTransaction { try connection.exec("BEGIN IMMEDIATE") }
    do {
      let stmt = try connection.prepare("DELETE FROM records WHERE id = ?")
      defer { stmt.finalize() }
      for id in ids {
        stmt.reset()
        stmt.bindText(1, id.uuidString)
        _ = try stmt.step()
      }
      if needsOwnTransaction { try connection.exec("COMMIT") }
    } catch {
      if needsOwnTransaction { try? connection.exec("ROLLBACK") }
      throw error
    }
  }

  /// Dual-gate retention: evict over-age records first, then over-count records.
  /// Pinned, favourite, and retentionExempt records are never touched.
  private func enforceRetention() throws {
    let now = Date().timeIntervalSince1970
    let ageCutoff = now - Double(retentionPolicy.maxAgeDays * 86_400)

    // Non-exempt records sorted newest → oldest
    let nonExempt = indexByHash.values
      .filter { !$0.isPinned && !$0.isFavorite && !$0.retentionExempt }
      .sorted { $0.lastCopiedAt > $1.lastCopiedAt }

    var deathRow: [UUID] = []

    // Gate 1: over-age
    for record in nonExempt where record.lastCopiedAt.timeIntervalSince1970 < ageCutoff {
      deathRow.append(record.id)
    }

    // Gate 2: over-count (oldest records at the tail of `nonExempt`)
    if nonExempt.count > retentionPolicy.maxCount {
      let overflow = nonExempt.suffix(nonExempt.count - retentionPolicy.maxCount)
      for record in overflow where !deathRow.contains(record.id) {
        deathRow.append(record.id)
      }
    }

    guard !deathRow.isEmpty else { return }

    let removedHashes = indexByHash.values
      .filter { deathRow.contains($0.id) }
      .map(\.contentHash)
    try deleteRecords(ids: deathRow)
    for hash in removedHashes {
      indexByHash.removeValue(forKey: hash)
    }
  }

  // MARK: - Static helpers (callable before actor isolation in init)

  private static func loadInitialIndex(connection: SQLiteConnection) throws -> [String: ClipboardRecord] {
    var index: [String: ClipboardRecord] = [:]
    let stmt = try connection.prepare(
      """
      SELECT id, content_hash, primary_type, title, plain_preview,
             source_bundle, source_app, source_device,
             created_at, last_copied_at, copy_count,
             is_pinned, is_favorite, group_ids_json, retention_exempt,
             metadata_json, pasteboard_types_json, payload_ref
      FROM records
      """
    )
    defer { stmt.finalize() }
    while try stmt.step() == SQLITE_ROW {
      let record = try decodeRecord(from: stmt)
      index[record.contentHash] = record
    }
    SQLiteHistoryStore.logger.info("loaded \(index.count) records into memory index")
    return index
  }

  private static func decodeRecord(from stmt: Statement) throws -> ClipboardRecord {
    guard let idString = stmt.columnText(0), let id = UUID(uuidString: idString) else {
      throw StorageError.underlying("invalid id column")
    }
    return ClipboardRecord(
      id: id,
      contentHash: stmt.columnText(1) ?? "",
      primaryType: ClipboardContentType(rawValue: stmt.columnText(2) ?? "text") ?? .text,
      title: stmt.columnText(3) ?? "",
      plainTextPreview: stmt.columnText(4),
      sourceAppBundleId: stmt.columnText(5),
      sourceAppName: stmt.columnText(6),
      sourceDeviceHint: ClipboardSourceDeviceHint(rawValue: stmt.columnText(7) ?? "local") ?? .local,
      createdAt: Date(timeIntervalSince1970: stmt.columnDouble(8)),
      lastCopiedAt: Date(timeIntervalSince1970: stmt.columnDouble(9)),
      copyCount: stmt.columnInt(10),
      isPinned: stmt.columnBool(11),
      isFavorite: stmt.columnBool(12),
      groupIds: try decodeJSON([String].self, from: stmt.columnText(13) ?? "[]"),
      retentionExempt: stmt.columnBool(14),
      metadata: try decodeJSONOptional(LargeTextMetadata.self, from: stmt.columnText(15)),
      pasteboardTypes: Set(try decodeJSON([String].self, from: stmt.columnText(16) ?? "[]"))
    )
  }

  private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? "null"
  }

  private static func encodeJSONOptional<T: Encodable>(_ value: T?) throws -> String? {
    guard let value else { return nil }
    return try encodeJSON(value)
  }

  private static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
  }

  private static func decodeJSONOptional<T: Decodable>(_ type: T.Type, from text: String?) throws -> T? {
    guard let text else { return nil }
    return try JSONDecoder().decode(type, from: Data(text.utf8))
  }
}
