import Foundation

public struct ImportSourceDiscovery {
  private let homeDirectory: URL
  private let fileManager: FileManager

  public init(
    homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
    fileManager: FileManager = .default
  ) {
    self.homeDirectory = homeDirectory
    self.fileManager = fileManager
  }

  public func discoverAutomaticSources() -> [ImportSourceCandidate] {
    var candidates: [ImportSourceCandidate] = []

    if let maccy = automaticCandidate(
      kind: .maccy,
      displayName: "Maccy",
      databaseURL: standardMaccyURL,
      appBundleID: "org.p0deje.Maccy",
      appURL: URL(fileURLWithPath: "/Applications/Maccy.app"),
      defaultSelected: true
    ), maccy.schemaKind == .maccy {
      candidates.append(maccy)
    }

    let cloud = automaticCandidate(
      kind: .clipasteCloud,
      displayName: "Clipaste Cloud",
      databaseURL: standardClipasteCloudURL,
      appBundleID: "com.gangz1o.clipaste",
      appURL: URL(fileURLWithPath: "/Applications/Clipaste.app"),
      defaultSelected: true
    )
    let cloudIsValid = cloud?.schemaKind == .clipaste

    let local = automaticCandidate(
      kind: .clipasteLocal,
      displayName: "Clipaste Local",
      databaseURL: standardClipasteLocalURL,
      appBundleID: "com.gangz1o.clipaste",
      appURL: URL(fileURLWithPath: "/Applications/Clipaste.app"),
      defaultSelected: !cloudIsValid
    )

    if let cloud, cloud.schemaKind == .clipaste {
      candidates.append(cloud)
    }
    if let local, local.schemaKind == .clipaste {
      candidates.append(local)
    }

    return candidates
  }

  public func classifyManualDatabase(_ url: URL) throws -> ImportSourceCandidate {
    let schema = try schemaKind(for: url)
    let kind: ImportSourceKind
    switch schema {
    case .maccy:
      kind = .manualMaccy
    case .clipaste:
      kind = .manualClipaste
    case .unknown:
      kind = .manualMaccy
    }

    return try candidate(
      kind: kind,
      displayName: url.lastPathComponent,
      databaseURL: url,
      appBundleID: nil,
      appURL: nil,
      defaultSelected: schema != .unknown,
      schema: schema
    )
  }

  private var standardMaccyURL: URL {
    homeDirectory.appendingPathComponent(
      "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite"
    )
  }

  private var standardClipasteCloudURL: URL {
    homeDirectory.appendingPathComponent(
      "Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-cloud.store"
    )
  }

  private var standardClipasteLocalURL: URL {
    homeDirectory.appendingPathComponent(
      "Library/Containers/com.gangz1o.clipaste/Data/Library/Application Support/com.gangz1o.clipaste/Stores/clipboard-local.store"
    )
  }

  private func automaticCandidate(
    kind: ImportSourceKind,
    displayName: String,
    databaseURL: URL,
    appBundleID: String,
    appURL: URL,
    defaultSelected: Bool
  ) -> ImportSourceCandidate? {
    guard fileManager.fileExists(atPath: databaseURL.path),
          fileManager.isReadableFile(atPath: databaseURL.path) else {
      return nil
    }

    return try? candidate(
      kind: kind,
      displayName: displayName,
      databaseURL: databaseURL,
      appBundleID: appBundleID,
      appURL: appURL,
      defaultSelected: defaultSelected
    )
  }

  private func candidate(
    kind: ImportSourceKind,
    displayName: String,
    databaseURL: URL,
    appBundleID: String?,
    appURL: URL?,
    defaultSelected: Bool,
    schema knownSchema: ImportSchemaKind? = nil
  ) throws -> ImportSourceCandidate {
    guard fileManager.fileExists(atPath: databaseURL.path) else {
      throw CocoaError(.fileNoSuchFile)
    }

    let schema = try knownSchema ?? schemaKind(for: databaseURL)
    let attributes = try? fileManager.attributesOfItem(atPath: databaseURL.path)
    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    let lastModified = attributes?[.modificationDate] as? Date
    let counts = try sourceCounts(databaseURL: databaseURL, schema: schema)

    return ImportSourceCandidate(
      id: "\(kind.rawValue):\(databaseURL.path)",
      kind: kind,
      displayName: displayName,
      databaseURL: databaseURL,
      appBundleID: appBundleID,
      appVersion: appVersion(at: appURL),
      storeSizeBytes: size,
      recordCount: counts.recordCount,
      typeDistribution: counts.typeDistribution,
      lastModifiedAt: lastModified,
      schemaKind: schema,
      schemaStatus: schema == .unknown ? "Unsupported schema" : "OK",
      isDefaultSelected: defaultSelected && schema != .unknown
    )
  }

  private func schemaKind(for url: URL) throws -> ImportSchemaKind {
    let database = try ExternalSQLiteDatabase(path: url.path)

    if try isMaccySchema(database) {
      return .maccy
    }
    if try isClipasteSchema(database) {
      return .clipaste
    }
    return .unknown
  }

  private func isMaccySchema(_ database: ExternalSQLiteDatabase) throws -> Bool {
    try database.hasTable("ZHISTORYITEM")
      && database.hasTable("ZHISTORYITEMCONTENT")
      && database.hasColumns(
        [
          "Z_PK",
          "ZFIRSTCOPIEDAT",
          "ZLASTCOPIEDAT",
          "ZNUMBEROFCOPIES",
          "ZAPPLICATION",
          "ZPIN",
          "ZTITLE"
        ],
        in: "ZHISTORYITEM"
      )
      && database.hasColumns(
        [
          "Z_PK",
          "ZITEM",
          "ZTYPE",
          "ZVALUE"
        ],
        in: "ZHISTORYITEMCONTENT"
      )
  }

  private func isClipasteSchema(_ database: ExternalSQLiteDatabase) throws -> Bool {
    try database.hasTable("ZCLIPBOARDRECORD")
      && database.hasColumns(
        [
          "Z_PK",
          "ZID",
          "ZTIMESTAMP",
          "ZAPPBUNDLEID",
          "ZAPPLOCALIZEDNAME",
          "ZCONTENTHASH",
          "ZCUSTOMTITLE",
          "ZGROUPID",
          "ZGROUPIDSRAW",
          "ZIMAGEUTTYPE",
          "ZLINKTITLE",
          "ZPLAINTEXT",
          "ZTYPERAWVALUE",
          "ZISPINNED",
          "ZIMAGEDATA",
          "ZRTFDATA"
        ],
        in: "ZCLIPBOARDRECORD"
      )
  }

  private func sourceCounts(
    databaseURL: URL,
    schema: ImportSchemaKind
  ) throws -> (recordCount: Int?, typeDistribution: [String: Int]) {
    let database = try ExternalSQLiteDatabase(path: databaseURL.path)

    switch schema {
    case .maccy:
      let recordCount = try database.intScalar("SELECT COUNT(*) FROM ZHISTORYITEM")
      return try (
        recordCount,
        typeDistribution(
          in: database,
          sql: "SELECT ZTYPE, COUNT(*) FROM ZHISTORYITEMCONTENT GROUP BY ZTYPE"
        )
      )

    case .clipaste:
      let recordCount = try database.intScalar("SELECT COUNT(*) FROM ZCLIPBOARDRECORD")
      return try (
        recordCount,
        typeDistribution(
          in: database,
          sql: "SELECT ZTYPERAWVALUE, COUNT(*) FROM ZCLIPBOARDRECORD GROUP BY ZTYPERAWVALUE"
        )
      )

    case .unknown:
      return (nil, [:])
    }
  }

  private func typeDistribution(
    in database: ExternalSQLiteDatabase,
    sql: String
  ) throws -> [String: Int] {
    var distribution: [String: Int] = [:]
    try database.rows(sql) { statement in
      guard let type = statement.columnText(0) else { return }
      distribution[type] = statement.columnInt(1)
    }
    return distribution
  }

  private func appVersion(at appURL: URL?) -> String? {
    guard let appURL else { return nil }
    return Bundle(url: appURL)?
      .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
  }
}
