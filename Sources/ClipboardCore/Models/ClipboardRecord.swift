import Foundation

public enum ClipboardPayload: Equatable, Sendable {
  case text(String)
  case richText(plainText: String, rtfData: Data)
  case image(data: Data, uti: String)
  case fileURLs([URL])
}

public struct LargeTextMetadata: Codable, Equatable, Sendable {
  public let byteSize: Int
  public let lineCountEstimate: Int
  public let contentClass: LargeTextContentClass
  public let previewExcerpt: String
  public let tailExcerpt: String
  public let blobStoragePolicy: BlobStoragePolicy
  public let indexingState: IndexingState

  public init(
    byteSize: Int,
    lineCountEstimate: Int,
    contentClass: LargeTextContentClass,
    previewExcerpt: String,
    tailExcerpt: String,
    blobStoragePolicy: BlobStoragePolicy = .summaryOnly,
    indexingState: IndexingState = .excerptIndexed
  ) {
    self.byteSize = byteSize
    self.lineCountEstimate = lineCountEstimate
    self.contentClass = contentClass
    self.previewExcerpt = previewExcerpt
    self.tailExcerpt = tailExcerpt
    self.blobStoragePolicy = blobStoragePolicy
    self.indexingState = indexingState
  }
}

public struct ClipboardCapture: Equatable, Sendable {
  public let payload: ClipboardPayload
  public let pasteboardTypes: Set<String>
  public let sourceAppBundleId: String?
  public let sourceAppName: String?
  public let capturedAt: Date

  public init(
    payload: ClipboardPayload,
    pasteboardTypes: Set<String>,
    sourceAppBundleId: String?,
    sourceAppName: String?,
    capturedAt: Date
  ) {
    self.payload = payload
    self.pasteboardTypes = pasteboardTypes
    self.sourceAppBundleId = sourceAppBundleId
    self.sourceAppName = sourceAppName
    self.capturedAt = capturedAt
  }

  public var isUniversalClipboard: Bool {
    pasteboardTypes.contains("com.apple.is-remote-clipboard")
  }
}

public struct ClipboardRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var contentHash: String
  public var primaryType: ClipboardContentType
  public var title: String
  public var plainTextPreview: String?
  public var sourceAppBundleId: String?
  public var sourceAppName: String?
  public var sourceDeviceHint: ClipboardSourceDeviceHint
  public var createdAt: Date
  public var lastCopiedAt: Date
  public var copyCount: Int
  public var isPinned: Bool
  public var isFavorite: Bool
  public var groupIds: [String]
  public var retentionExempt: Bool
  public var metadata: LargeTextMetadata?
  public var pasteboardTypes: Set<String>

  public init(
    id: UUID,
    contentHash: String,
    primaryType: ClipboardContentType,
    title: String,
    plainTextPreview: String?,
    sourceAppBundleId: String?,
    sourceAppName: String?,
    sourceDeviceHint: ClipboardSourceDeviceHint,
    createdAt: Date,
    lastCopiedAt: Date,
    copyCount: Int,
    isPinned: Bool,
    isFavorite: Bool,
    groupIds: [String],
    retentionExempt: Bool,
    metadata: LargeTextMetadata?,
    pasteboardTypes: Set<String>
  ) {
    self.id = id
    self.contentHash = contentHash
    self.primaryType = primaryType
    self.title = title
    self.plainTextPreview = plainTextPreview
    self.sourceAppBundleId = sourceAppBundleId
    self.sourceAppName = sourceAppName
    self.sourceDeviceHint = sourceDeviceHint
    self.createdAt = createdAt
    self.lastCopiedAt = lastCopiedAt
    self.copyCount = copyCount
    self.isPinned = isPinned
    self.isFavorite = isFavorite
    self.groupIds = groupIds
    self.retentionExempt = retentionExempt
    self.metadata = metadata
    self.pasteboardTypes = pasteboardTypes
  }

  public var isLargeContent: Bool {
    metadata != nil
  }
}
