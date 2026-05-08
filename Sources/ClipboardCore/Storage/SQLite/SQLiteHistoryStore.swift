import Foundation
import SQLite3
import os.log

public actor SQLiteHistoryStore: HistoryStore {
  private let connection: SQLiteConnection
  private var indexByHash: [String: ClipboardRecord] = [:]
  private static let logger = Logger(subsystem: "clipboard.storage", category: "SQLiteHistoryStore")

  public init(databaseFile: URL) throws {
    let dir = databaseFile.deletingLastPathComponent()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path) {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    self.connection = try SQLiteConnection(path: databaseFile.path)
    try SQLiteSchema.setupPragmas(connection: connection)
    try SQLiteSchema.migrate(connection: connection)
    self.indexByHash = try Self.loadInitialIndex(connection: connection)
  }

  /// Clears the in-memory index. Does not close the underlying connection.
  public func close() {
    indexByHash.removeAll()
  }

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    if let existing = indexByHash[record.contentHash] {
      var updated = existing
      updated.copyCount += 1
      updated.lastCopiedAt = record.lastCopiedAt
      try writeRecord(updated)
      indexByHash[updated.contentHash] = updated
      return updated
    }

    try writeRecord(record)
    indexByHash[record.contentHash] = record
    return record
  }

  public func fetchAll() async throws -> [ClipboardRecord] {
    indexByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
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
    indexByHash.count
  }

  public func removeAll() async throws {
    try connection.exec("DELETE FROM records")
    indexByHash.removeAll()
  }

  public func evictOldest(percent: Double) async throws -> Int {
    // Placeholder; real implementation arrives in Task 11
    return 0
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
