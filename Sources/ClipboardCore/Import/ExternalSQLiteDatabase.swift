import Foundation
import SQLite3

final class ExternalSQLiteDatabase {
  private let connection: SQLiteConnection

  init(path: String) throws {
    connection = try SQLiteConnection(path: path, readOnly: true)
  }

  func hasTable(_ name: String) throws -> Bool {
    let statement = try connection.prepare(
      "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?"
    )
    defer { statement.finalize() }
    statement.bindText(1, name)

    let rc = try statement.step()
    guard rc == SQLITE_ROW else {
      throw StorageError.underlying("sqlite table lookup returned rc=\(rc)")
    }
    return statement.columnInt(0) > 0
  }

  func columns(in table: String) throws -> Set<String> {
    let quotedTable = try quoteIdentifier(table)
    var result = Set<String>()

    try rows("PRAGMA table_info(\(quotedTable))") { statement in
      if let name = statement.columnText(1) {
        result.insert(name)
      }
    }

    return result
  }

  func hasColumns(_ names: Set<String>, in table: String) throws -> Bool {
    let existingColumns = try columns(in: table)
    return names.isSubset(of: existingColumns)
  }

  func intScalar(_ sql: String) throws -> Int {
    try connection.intScalar(sql)
  }

  func rows(
    _ sql: String,
    bind: ((Statement) -> Void)? = nil,
    read: (Statement) throws -> Void
  ) throws {
    let statement = try connection.prepare(sql)
    defer { statement.finalize() }
    bind?(statement)

    while try statement.step() == SQLITE_ROW {
      try read(statement)
    }
  }

  private func quoteIdentifier(_ value: String) throws -> String {
    let pattern = #"^[A-Za-z_][A-Za-z0-9_]*$"#
    guard value.range(of: pattern, options: .regularExpression) != nil else {
      throw StorageError.underlying("unsafe sqlite identifier \(value)")
    }
    return "\"\(value)\""
  }
}
