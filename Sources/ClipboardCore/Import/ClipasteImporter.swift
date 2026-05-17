import Foundation
import SQLite3

public struct ClipasteImporter: Sendable {
  private let source: ImportSourceKind

  public init(source: ImportSourceKind) {
    self.source = source
  }

  public func importRecords(from databaseURL: URL) throws -> [ImportedRecord] {
    let database = try ExternalSQLiteDatabase(path: databaseURL.path)
    let groups = try loadGroups(in: database)
    var records: [ImportedRecord] = []

    try database.rows(
      """
      SELECT Z_PK, ZID, ZTIMESTAMP, ZAPPBUNDLEID, ZAPPLOCALIZEDNAME, ZCONTENTHASH,
             ZCUSTOMTITLE, ZGROUPID, ZGROUPIDSRAW, ZIMAGEUTTYPE, ZLINKTITLE,
             ZPLAINTEXT, ZTYPERAWVALUE, ZISPINNED, ZIMAGEDATA, ZRTFDATA
      FROM ZCLIPBOARDRECORD
      ORDER BY Z_PK
      """
    ) { statement in
      guard let record = makeRecord(from: statement, groups: groups) else { return }
      records.append(record)
    }

    return records
  }

  private func loadGroups(in database: ExternalSQLiteDatabase) throws -> [String: String] {
    guard try database.hasTable("ZCLIPBOARDGROUPMODEL"),
          try database.hasColumns(["ZID", "ZNAME"], in: "ZCLIPBOARDGROUPMODEL") else {
      return [:]
    }

    var groups: [String: String] = [:]
    try database.rows("SELECT ZID, ZNAME FROM ZCLIPBOARDGROUPMODEL") { statement in
      guard let id = nonEmptyString(statement.columnText(0)),
            let name = nonEmptyString(statement.columnText(1)) else {
        return
      }
      groups[id] = name
    }
    return groups
  }

  private func makeRecord(from statement: Statement, groups: [String: String]) -> ImportedRecord? {
    let primaryKey = statement.columnInt(0)
    let sourceRecordID = sourceRecordID(from: statement, primaryKey: primaryKey)
    let timestamp = statement.columnDouble(2)
    let appBundleID = nonEmptyString(statement.columnText(3))
    let appName = nonEmptyString(statement.columnText(4))
    let contentHash = nonEmptyString(statement.columnText(5))
    let customTitle = nonEmptyString(statement.columnText(6))
    let groupID = nonEmptyString(statement.columnText(7))
    let groupIDsRaw = nonEmptyString(statement.columnText(8))
    let imageUTType = nonEmptyString(statement.columnText(9))
    let linkTitle = nonEmptyString(statement.columnText(10))
    let plainText = nonEmptyString(statement.columnText(11))
    let rawType = nonEmptyString(statement.columnText(12))
    let isPinned = statement.columnBool(13)
    let imageData = statement.columnData(14)
    let rtfData = statement.columnData(15)

    guard let resolved = payload(
      rawType: rawType,
      plainText: plainText,
      imageUTType: imageUTType,
      imageData: imageData,
      rtfData: rtfData
    ) else {
      return nil
    }

    let date = Date(timeIntervalSinceReferenceDate: timestamp)
    return ImportedRecord(
      source: source,
      sourceRecordID: sourceRecordID,
      payload: resolved.payload,
      primaryType: resolved.primaryType,
      pasteboardTypes: resolved.pasteboardTypes,
      title: title(
        customTitle: customTitle,
        linkTitle: linkTitle,
        plainText: plainText,
        payload: resolved.payload
      ),
      plainTextPreview: plainTextPreview(payload: resolved.payload, plainText: plainText),
      sourceAppBundleId: appBundleID,
      sourceAppName: appName,
      createdAt: date,
      lastCopiedAt: date,
      copyCount: 1,
      isPinned: isPinned,
      isFavorite: false,
      groupNames: groupNames(groupID: groupID, groupIDsRaw: groupIDsRaw, groups: groups),
      sourceDeviceHint: .imported,
      externalContentHash: contentHash,
      warnings: resolved.warnings
    )
  }
}

private func sourceRecordID(from statement: Statement, primaryKey: Int) -> String {
  if sqlite3_column_type(statement.handle, 1) == SQLITE_BLOB,
     let data = statement.columnData(1),
     !data.isEmpty {
    return hexString(from: data)
  }

  return nonEmptyString(statement.columnText(1)) ?? "\(primaryKey)"
}

private func hexString(from data: Data) -> String {
  data.map { String(format: "%02X", $0) }.joined()
}

private struct ClipastePayload {
  let payload: ClipboardPayload
  let primaryType: ClipboardContentType
  let pasteboardTypes: Set<String>
  let warnings: [String]
}

private func payload(
  rawType: String?,
  plainText: String?,
  imageUTType: String?,
  imageData: Data?,
  rtfData: Data?
) -> ClipastePayload? {
  switch normalizedType(rawType) {
  case "image":
    guard let imageData, let imageUTType else { return nil }
    return ClipastePayload(
      payload: .image(data: imageData, uti: imageUTType),
      primaryType: .image,
      pasteboardTypes: [imageUTType],
      warnings: []
    )

  case "richtext":
    guard let rtfData, let plainText else { return nil }
    return ClipastePayload(
      payload: .richText(plainText: plainText, rtfData: rtfData),
      primaryType: .richText,
      pasteboardTypes: ["public.rtf", "public.utf8-plain-text"],
      warnings: []
    )

  case "fileurl", "file":
    guard let urls = fileURLs(from: plainText), !urls.isEmpty else { return nil }
    return ClipastePayload(
      payload: .fileURLs(urls),
      primaryType: .file,
      pasteboardTypes: ["public.file-url"],
      warnings: []
    )

  case "link", "url":
    guard let plainText else { return nil }
    return ClipastePayload(
      payload: .text(plainText),
      primaryType: .link,
      pasteboardTypes: ["public.utf8-plain-text"],
      warnings: []
    )

  case "text", "plaintext", "plain":
    guard let plainText else { return nil }
    return ClipastePayload(
      payload: .text(plainText),
      primaryType: isSingleHTTPURL(plainText) ? .link : .text,
      pasteboardTypes: ["public.utf8-plain-text"],
      warnings: []
    )

  case "code":
    guard let plainText else { return nil }
    return ClipastePayload(
      payload: .text(plainText),
      primaryType: .text,
      pasteboardTypes: ["public.utf8-plain-text"],
      warnings: ["Clipaste code imported as text"]
    )

  default:
    return nil
  }
}

private func normalizedType(_ value: String?) -> String {
  nonEmptyString(value)?
    .replacingOccurrences(of: "_", with: "")
    .replacingOccurrences(of: "-", with: "")
    .lowercased() ?? ""
}

private func fileURLs(from value: String?) -> [URL]? {
  guard let value else { return nil }
  let parts = value
    .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\0" })
    .map(String.init)
  let candidates = parts.isEmpty ? [value] : parts
  let urls = candidates.compactMap { raw -> URL? in
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.isFileURL else { return nil }
    return url
  }
  return urls.isEmpty ? nil : urls
}

private func groupNames(
  groupID: String?,
  groupIDsRaw: String?,
  groups: [String: String]
) -> [String] {
  var names: [String] = []
  var seen = Set<String>()

  let ids = parsedGroupIDs(from: groupIDsRaw)
  for id in ids {
    guard let name = groups[id], !seen.contains(name) else { continue }
    names.append(name)
    seen.insert(name)
  }

  if let groupID, let name = groups[groupID], !seen.contains(name) {
    names.append(name)
    seen.insert(name)
  }

  return names.isEmpty ? ["Clipaste Import"] : names
}

private func parsedGroupIDs(from value: String?) -> [String] {
  guard let value else { return [] }
  let separators = CharacterSet(charactersIn: "[],;\"'\n\r\t ")
  return value
    .components(separatedBy: separators)
    .compactMap(nonEmptyString)
}

private func title(
  customTitle: String?,
  linkTitle: String?,
  plainText: String?,
  payload: ClipboardPayload
) -> String {
  if let customTitle {
    return truncated(customTitle)
  }
  if let linkTitle {
    return truncated(linkTitle)
  }
  if let plainText {
    return truncated(plainText)
  }

  switch payload {
  case .text:
    return "Text"
  case .richText:
    return "Rich Text"
  case .image:
    return "Image"
  case .fileURLs(let urls):
    guard let first = urls.first else { return "File" }
    return first.lastPathComponent.isEmpty ? first.absoluteString : first.lastPathComponent
  }
}

private func truncated(_ value: String, limit: Int = 160) -> String {
  guard value.count > limit else { return value }
  return String(value.prefix(limit))
}

private func plainTextPreview(payload: ClipboardPayload, plainText: String?) -> String? {
  switch payload {
  case .text:
    return plainText
  case .richText:
    return plainText
  case .image:
    return plainText
  case .fileURLs:
    return nil
  }
}

private func nonEmptyString(_ value: String?) -> String? {
  guard let value else { return nil }
  return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
}

private func isSingleHTTPURL(_ value: String) -> Bool {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
        let url = URL(string: trimmed),
        let scheme = url.scheme?.lowercased(),
        (scheme == "http" || scheme == "https"),
        url.host != nil else {
    return false
  }
  return true
}
