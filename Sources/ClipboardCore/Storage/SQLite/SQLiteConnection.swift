import Foundation
import SQLite3

/// Thin wrapper around the sqlite3 C API exposing only what this project needs.
/// Methods assume the caller provides isolation (e.g. an enclosing actor) — no internal locking.
final class SQLiteConnection {
  private var db: OpaquePointer?

  static let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1)!,
    to: sqlite3_destructor_type.self
  )

  init(path: String) throws {
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let rc = sqlite3_open_v2(path, &handle, flags, nil)
    guard rc == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw StorageError.underlying("sqlite3_open_v2 rc=\(rc)")
    }
    self.db = handle
  }

  deinit {
    if let db { sqlite3_close(db) }
  }

  /// Executes SQL with no result rows (CREATE / PRAGMA / BEGIN / COMMIT, etc.).
  func exec(_ sql: String) throws {
    guard let db else { throw StorageError.underlying("connection closed") }
    var errMsg: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
    if rc != SQLITE_OK {
      let msg = errMsg.map { String(cString: $0) } ?? "rc=\(rc)"
      sqlite3_free(errMsg)
      throw Self.translate(rc, message: msg)
    }
  }

  /// Prepares a statement; caller is responsible for finalize (typically via defer).
  func prepare(_ sql: String) throws -> Statement {
    guard let db else { throw StorageError.underlying("connection closed") }
    var stmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    guard rc == SQLITE_OK, let stmt else {
      throw Self.translate(rc, message: "prepare rc=\(rc) sql=\(sql)")
    }
    return Statement(handle: stmt)
  }

  /// Scalar query (e.g. SELECT changes()).
  func intScalar(_ sql: String) throws -> Int {
    let stmt = try prepare(sql)
    defer { stmt.finalize() }
    let rc = sqlite3_step(stmt.handle)
    guard rc == SQLITE_ROW else { throw Self.translate(rc, message: "intScalar step rc=\(rc)") }
    return Int(sqlite3_column_int64(stmt.handle, 0))
  }

  // Compound SQLITE_IOERR_* macros are bitwise expressions unavailable in Swift import;
  // compute the numeric values manually from sqlite3.h:
  //   SQLITE_IOERR_WRITE = SQLITE_IOERR | (3<<8)  = 10 | 768  = 778
  //   SQLITE_IOERR_NOMEM = SQLITE_IOERR | (12<<8) = 10 | 3072 = 3082
  private static let SQLITE_IOERR_WRITE: Int32 = 778
  private static let SQLITE_IOERR_NOMEM: Int32 = 3082

  static func translate(_ rc: Int32, message: String) -> StorageError {
    switch rc {
    case SQLITE_FULL, SQLITE_IOERR_WRITE, SQLITE_IOERR_NOMEM:
      return .full
    default:
      return .underlying("sqlite rc=\(rc) \(message)")
    }
  }
}

/// RAII wrapper around a prepared statement. Caller holds a reference and eventually calls finalize().
final class Statement {
  let handle: OpaquePointer
  private var finalized = false

  init(handle: OpaquePointer) {
    self.handle = handle
  }

  deinit {
    if !finalized { sqlite3_finalize(handle) }
  }

  func finalize() {
    if !finalized {
      sqlite3_finalize(handle)
      finalized = true
    }
  }

  func reset() {
    sqlite3_reset(handle)
    sqlite3_clear_bindings(handle)
  }

  func bindText(_ index: Int32, _ value: String?) {
    if let value {
      sqlite3_bind_text(handle, index, value, -1, SQLiteConnection.SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(handle, index)
    }
  }

  func bindInt(_ index: Int32, _ value: Int) {
    sqlite3_bind_int64(handle, index, Int64(value))
  }

  func bindBool(_ index: Int32, _ value: Bool) {
    sqlite3_bind_int(handle, index, value ? 1 : 0)
  }

  func bindDouble(_ index: Int32, _ value: Double) {
    sqlite3_bind_double(handle, index, value)
  }

  func step() throws -> Int32 {
    let rc = sqlite3_step(handle)
    guard rc == SQLITE_ROW || rc == SQLITE_DONE else {
      throw SQLiteConnection.translate(rc, message: "step rc=\(rc)")
    }
    return rc
  }

  func columnText(_ index: Int32) -> String? {
    guard let cstr = sqlite3_column_text(handle, index) else { return nil }
    return String(cString: cstr)
  }

  func columnInt(_ index: Int32) -> Int {
    Int(sqlite3_column_int64(handle, index))
  }

  func columnBool(_ index: Int32) -> Bool {
    sqlite3_column_int(handle, index) != 0
  }

  func columnDouble(_ index: Int32) -> Double {
    sqlite3_column_double(handle, index)
  }

  func columnIsNull(_ index: Int32) -> Bool {
    sqlite3_column_type(handle, index) == SQLITE_NULL
  }
}
