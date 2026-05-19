import Foundation
import SQLite3

enum SQLiteSchema {
  static let currentVersion: Int = 2

  static func migrate(connection: SQLiteConnection) throws {
    let version = try connection.intScalar("PRAGMA user_version")
    if version < 1 {
      try migrateToV1(connection: connection)
    }
    if version < 2 {
      try migrateToV2(connection: connection)
    }
  }

  static func setupPragmas(connection: SQLiteConnection) throws {
    try connection.exec("PRAGMA journal_mode = WAL")
    try connection.exec("PRAGMA synchronous = NORMAL")
    try connection.exec("PRAGMA foreign_keys = ON")
    try connection.exec("PRAGMA auto_vacuum = INCREMENTAL")
  }

  private static func migrateToV1(connection: SQLiteConnection) throws {
    try connection.exec("""
      CREATE TABLE IF NOT EXISTS records (
          id              TEXT PRIMARY KEY,
          content_hash    TEXT NOT NULL UNIQUE,
          primary_type    TEXT NOT NULL,
          title           TEXT NOT NULL,
          plain_preview   TEXT,
          source_bundle   TEXT,
          source_app      TEXT,
          source_device   TEXT NOT NULL,
          created_at      REAL NOT NULL,
          last_copied_at  REAL NOT NULL,
          copy_count      INTEGER NOT NULL,
          is_pinned       INTEGER NOT NULL,
          is_favorite     INTEGER NOT NULL,
          group_ids_json  TEXT NOT NULL,
          retention_exempt INTEGER NOT NULL,
          metadata_json   TEXT,
          pasteboard_types_json TEXT NOT NULL,
          payload_ref     TEXT
      )
    """)
    try connection.exec("CREATE INDEX IF NOT EXISTS idx_last_copied_at ON records(last_copied_at DESC)")
    try connection.exec("CREATE INDEX IF NOT EXISTS idx_pinned_favorite ON records(is_pinned, is_favorite)")
    try connection.exec("PRAGMA user_version = 1")
  }

  private static func migrateToV2(connection: SQLiteConnection) throws {
    if try !hasColumn("pinned_at", in: "records", connection: connection) {
      try connection.exec("ALTER TABLE records ADD COLUMN pinned_at REAL")
    }
    try connection.exec("CREATE INDEX IF NOT EXISTS idx_pinned_at ON records(is_pinned, pinned_at DESC)")
    try connection.exec("PRAGMA user_version = 2")
  }

  private static func hasColumn(
    _ column: String,
    in table: String,
    connection: SQLiteConnection
  ) throws -> Bool {
    let stmt = try connection.prepare("PRAGMA table_info(\(table))")
    defer { stmt.finalize() }
    while try stmt.step() == SQLITE_ROW {
      if stmt.columnText(1) == column {
        return true
      }
    }
    return false
  }

  /// Backs up a corrupted database file. Returns the backup URL.
  static func backupCorruptedDatabase(at path: URL) throws -> URL {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
    let suffix = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
    let backup = path.deletingLastPathComponent()
      .appendingPathComponent("clipboard.corrupt.\(suffix).sqlite")
    try FileManager.default.moveItem(at: path, to: backup)
    return backup
  }
}
