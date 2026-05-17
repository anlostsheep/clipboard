import Foundation

public enum ImportSourceKind: String, Codable, Equatable, Sendable {
  case maccy
  case clipasteCloud
  case clipasteLocal
  case manualMaccy
  case manualClipaste
}

public enum ImportSchemaKind: String, Codable, Equatable, Sendable {
  case maccy
  case clipaste
  case unknown
}

public enum ImportReportStatus: String, Codable, Equatable, Sendable {
  case completed
  case cancelled
  case failed
}

public struct ImportSourceCandidate: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  public let kind: ImportSourceKind
  public let displayName: String
  public let databaseURL: URL
  public let appBundleID: String?
  public let appVersion: String?
  public let storeSizeBytes: Int64
  public let recordCount: Int?
  public let typeDistribution: [String: Int]
  public let lastModifiedAt: Date?
  public let schemaKind: ImportSchemaKind
  public let schemaStatus: String
  public let isDefaultSelected: Bool

  public init(
    id: String,
    kind: ImportSourceKind,
    displayName: String,
    databaseURL: URL,
    appBundleID: String?,
    appVersion: String?,
    storeSizeBytes: Int64,
    recordCount: Int?,
    typeDistribution: [String: Int],
    lastModifiedAt: Date?,
    schemaKind: ImportSchemaKind,
    schemaStatus: String,
    isDefaultSelected: Bool
  ) {
    self.id = id
    self.kind = kind
    self.displayName = displayName
    self.databaseURL = databaseURL
    self.appBundleID = appBundleID
    self.appVersion = appVersion
    self.storeSizeBytes = storeSizeBytes
    self.recordCount = recordCount
    self.typeDistribution = typeDistribution
    self.lastModifiedAt = lastModifiedAt
    self.schemaKind = schemaKind
    self.schemaStatus = schemaStatus
    self.isDefaultSelected = isDefaultSelected
  }
}

public struct ImportedRecord: Equatable, Sendable {
  public let source: ImportSourceKind
  public let sourceRecordID: String
  public let payload: ClipboardPayload
  public let primaryType: ClipboardContentType
  public let pasteboardTypes: Set<String>
  public let title: String
  public let plainTextPreview: String?
  public let sourceAppBundleId: String?
  public let sourceAppName: String?
  public let createdAt: Date
  public let lastCopiedAt: Date
  public let copyCount: Int
  public let isPinned: Bool
  public let isFavorite: Bool
  public let groupNames: [String]
  public let sourceDeviceHint: ClipboardSourceDeviceHint
  public let externalContentHash: String?
  public let warnings: [String]

  public init(
    source: ImportSourceKind,
    sourceRecordID: String,
    payload: ClipboardPayload,
    primaryType: ClipboardContentType,
    pasteboardTypes: Set<String>,
    title: String,
    plainTextPreview: String?,
    sourceAppBundleId: String?,
    sourceAppName: String?,
    createdAt: Date,
    lastCopiedAt: Date,
    copyCount: Int,
    isPinned: Bool,
    isFavorite: Bool,
    groupNames: [String],
    sourceDeviceHint: ClipboardSourceDeviceHint,
    externalContentHash: String?,
    warnings: [String]
  ) {
    self.source = source
    self.sourceRecordID = sourceRecordID
    self.payload = payload
    self.primaryType = primaryType
    self.pasteboardTypes = pasteboardTypes
    self.title = title
    self.plainTextPreview = plainTextPreview
    self.sourceAppBundleId = sourceAppBundleId
    self.sourceAppName = sourceAppName
    self.createdAt = createdAt
    self.lastCopiedAt = lastCopiedAt
    self.copyCount = max(1, copyCount)
    self.isPinned = isPinned
    self.isFavorite = isFavorite
    self.groupNames = groupNames
    self.sourceDeviceHint = sourceDeviceHint
    self.externalContentHash = externalContentHash
    self.warnings = warnings
  }
}

public struct ImportFailure: Codable, Equatable, Sendable {
  public let source: ImportSourceKind
  public let sourceRecordID: String?
  public let titleOrPreview: String?
  public let reason: String

  public init(
    source: ImportSourceKind,
    sourceRecordID: String?,
    titleOrPreview: String?,
    reason: String
  ) {
    self.source = source
    self.sourceRecordID = sourceRecordID
    self.titleOrPreview = titleOrPreview
    self.reason = reason
  }
}

public struct ImportReport: Codable, Equatable, Sendable {
  public var id: UUID
  public var createdAt: Date
  public var status: ImportReportStatus
  public var sources: [String]
  public var schemaVersions: [String: String]
  public var scanned: Int
  public var imported: Int
  public var merged: Int
  public var replacedByNewest: Int
  public var skipped: Int
  public var failed: Int
  public var committedBatchCount: Int
  public var lastProcessedSourceRecordID: String?
  public var createdGroupIDs: [String]
  public var warnings: [String]
  public var failures: [ImportFailure]
  public var duration: TimeInterval
  public var appVersion: String
  public var reportSchemaVersion: Int

  public init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    status: ImportReportStatus,
    sources: [String],
    schemaVersions: [String: String] = [:],
    scanned: Int = 0,
    imported: Int = 0,
    merged: Int = 0,
    replacedByNewest: Int = 0,
    skipped: Int = 0,
    failed: Int = 0,
    committedBatchCount: Int = 0,
    lastProcessedSourceRecordID: String? = nil,
    createdGroupIDs: [String] = [],
    warnings: [String] = [],
    failures: [ImportFailure] = [],
    duration: TimeInterval = 0,
    appVersion: String = "unknown",
    reportSchemaVersion: Int = 1
  ) {
    self.id = id
    self.createdAt = createdAt
    self.status = status
    self.sources = sources
    self.schemaVersions = schemaVersions
    self.scanned = scanned
    self.imported = imported
    self.merged = merged
    self.replacedByNewest = replacedByNewest
    self.skipped = skipped
    self.failed = failed
    self.committedBatchCount = committedBatchCount
    self.lastProcessedSourceRecordID = lastProcessedSourceRecordID
    self.createdGroupIDs = createdGroupIDs
    self.warnings = warnings
    self.failures = failures
    self.duration = duration
    self.appVersion = appVersion
    self.reportSchemaVersion = reportSchemaVersion
  }
}
