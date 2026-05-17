import Foundation

public struct MaccyImporter: Sendable {
  private let source: ImportSourceKind

  public init(source: ImportSourceKind) {
    self.source = source
  }

  public func importRecords(from databaseURL: URL) throws -> [ImportedRecord] {
    let database = try ExternalSQLiteDatabase(path: databaseURL.path)
    var records: [ImportedRecord] = []

    try database.rows(
      """
      SELECT Z_PK, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT, ZNUMBEROFCOPIES, ZAPPLICATION, ZPIN, ZTITLE
      FROM ZHISTORYITEM
      ORDER BY Z_PK
      """
    ) { item in
      let itemID = item.columnInt(0)
      let contents = try contents(for: itemID, in: database)
      guard let payload = payload(from: contents) else { return }

      let plainText = textValue(in: contents)
      let title = normalizedTitle(
        item.columnText(6),
        payload: payload.payload,
        plainText: plainText
      )
      let sourceApplication = sourceApplication(
        pasteboardSourceBundleID: sourceBundleID(in: contents),
        application: item.columnText(4)
      )

      records.append(ImportedRecord(
        source: source,
        sourceRecordID: "\(itemID)",
        payload: payload.payload,
        primaryType: payload.primaryType,
        pasteboardTypes: Set(contents.map(\.type)),
        title: title,
        plainTextPreview: plainTextPreview(payload: payload.payload, plainText: plainText),
        sourceAppBundleId: sourceApplication.bundleID,
        sourceAppName: sourceApplication.name,
        createdAt: maccyDate(from: item.columnDouble(1)),
        lastCopiedAt: maccyDate(from: item.columnDouble(2)),
        copyCount: max(1, item.columnInt(3)),
        isPinned: !(item.columnText(5) ?? "").isEmpty,
        isFavorite: false,
        groupNames: ["Maccy Import"],
        sourceDeviceHint: isUniversalClipboard(contents) ? .universalClipboard : .imported,
        externalContentHash: nil,
        warnings: warnings(from: contents)
      ))
    }

    return records
  }

  private func contents(for itemID: Int, in database: ExternalSQLiteDatabase) throws -> [MaccyContent] {
    var contents: [MaccyContent] = []
    try database.rows(
      """
      SELECT ZTYPE, ZVALUE
      FROM ZHISTORYITEMCONTENT
      WHERE ZITEM = ?
      ORDER BY Z_PK
      """,
      bind: { statement in
        statement.bindInt(1, itemID)
      }
    ) { statement in
      guard let type = statement.columnText(0) else { return }
      contents.append(MaccyContent(type: type, data: statement.columnData(1) ?? Data()))
    }
    return contents
  }
}

private struct MaccyContent {
  let type: String
  let data: Data
}

private struct MaccyPayload {
  let payload: ClipboardPayload
  let primaryType: ClipboardContentType
}

private let imageTypes: Set<String> = [
  "public.heic",
  "public.png",
  "public.jpeg",
  "public.tiff"
]

private let richTextTypes: Set<String> = [
  "public.rtf"
]

private let fileURLTypes: Set<String> = [
  "public.file-url",
  "NSURLPboardType"
]

private let textTypes: Set<String> = [
  "public.utf8-plain-text",
  "NSStringPboardType"
]

private let metadataTypes: Set<String> = [
  "org.nspasteboard.source",
  "com.apple.is-remote-clipboard"
]

private func payload(from contents: [MaccyContent]) -> MaccyPayload? {
  if let image = contents.first(where: { imageTypes.contains($0.type) }) {
    return MaccyPayload(
      payload: .image(data: image.data, uti: image.type),
      primaryType: .image
    )
  }

  if let rtf = contents.first(where: { richTextTypes.contains($0.type) }) {
    return MaccyPayload(
      payload: .richText(plainText: textValue(in: contents) ?? "", rtfData: rtf.data),
      primaryType: .richText
    )
  }

  if let fileURLs = fileURLs(in: contents), !fileURLs.isEmpty {
    return MaccyPayload(payload: .fileURLs(fileURLs), primaryType: .file)
  }

  if let text = textValue(in: contents) {
    return MaccyPayload(
      payload: .text(text),
      primaryType: isSingleHTTPURL(text) ? .link : .text
    )
  }

  return nil
}

private func textValue(in contents: [MaccyContent]) -> String? {
  contents
    .first { textTypes.contains($0.type) }
    .flatMap { stringValue($0.data) }
}

private func fileURLs(in contents: [MaccyContent]) -> [URL]? {
  guard let content = contents.first(where: { fileURLTypes.contains($0.type) }),
        let value = stringValue(content.data) else {
    return nil
  }

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

private func sourceBundleID(in contents: [MaccyContent]) -> String? {
  contents
    .first { $0.type == "org.nspasteboard.source" }
    .flatMap { stringValue($0.data) }
    .flatMap(nonEmptyString)
}

private func sourceApplication(
  pasteboardSourceBundleID: String?,
  application: String?
) -> (bundleID: String?, name: String?) {
  let applicationName = application.flatMap(nonEmptyApplicationName)

  if let pasteboardSourceBundleID {
    return (pasteboardSourceBundleID, applicationName)
  }

  guard let application = nonEmptyString(application) else {
    return (nil, nil)
  }

  if looksLikeBundleIdentifier(application) {
    return (application, nil)
  }

  return (nil, application)
}

private func nonEmptyApplicationName(_ value: String?) -> String? {
  guard let value = nonEmptyString(value),
        !looksLikeBundleIdentifier(value) else {
    return nil
  }
  return value
}

private func looksLikeBundleIdentifier(_ value: String) -> Bool {
  value.contains(".") && !value.contains { $0.isWhitespace || $0.isNewline }
}

private func maccyDate(from value: Double) -> Date {
  Date(timeIntervalSinceReferenceDate: value)
}

private func isUniversalClipboard(_ contents: [MaccyContent]) -> Bool {
  contents.contains { $0.type == "com.apple.is-remote-clipboard" }
}

private func warnings(from contents: [MaccyContent]) -> [String] {
  contents
    .map(\.type)
    .filter { !supportedTypes.contains($0) }
    .map { "Unsupported Maccy pasteboard type: \($0)" }
}

private var supportedTypes: Set<String> {
  imageTypes
    .union(richTextTypes)
    .union(fileURLTypes)
    .union(textTypes)
    .union(metadataTypes)
}

private func normalizedTitle(
  _ rawTitle: String?,
  payload: ClipboardPayload,
  plainText: String?
) -> String {
  if let title = nonEmptyString(rawTitle) {
    return title
  }

  switch payload {
  case .text(let text):
    return text
  case .richText:
    return plainText.flatMap(nonEmptyString) ?? "Rich Text"
  case .image:
    return plainText.flatMap(nonEmptyString) ?? "Image"
  case .fileURLs(let urls):
    guard let first = urls.first else { return "File" }
    return first.lastPathComponent.isEmpty ? first.absoluteString : first.lastPathComponent
  }
}

private func plainTextPreview(payload: ClipboardPayload, plainText: String?) -> String? {
  switch payload {
  case .text(let text):
    return text
  case .richText:
    return plainText
  case .image:
    return plainText
  case .fileURLs:
    return nil
  }
}

private func stringValue(_ data: Data) -> String? {
  String(data: data, encoding: .utf8).flatMap(nonEmptyString)
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
