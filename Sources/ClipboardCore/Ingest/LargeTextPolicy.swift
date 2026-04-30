import Foundation

public struct LargeTextClassification: Equatable, Sendable {
  public let isLarge: Bool
  public let contentClass: LargeTextContentClass
  public let metadata: LargeTextMetadata?

  public init(isLarge: Bool, contentClass: LargeTextContentClass, metadata: LargeTextMetadata?) {
    self.isLarge = isLarge
    self.contentClass = contentClass
    self.metadata = metadata
  }
}

public struct LargeTextPolicy: Equatable, Sendable {
  public let largeTextBytes: Int
  public let extremeTextBytes: Int
  public let excerptLimit: Int
  private static let contentDetectionCharacterLimit = 8_192
  private static let lineEstimateByteLimit = 8_192

  public init(largeTextBytes: Int, extremeTextBytes: Int, excerptLimit: Int) {
    self.largeTextBytes = largeTextBytes
    self.extremeTextBytes = extremeTextBytes
    self.excerptLimit = excerptLimit
  }

  public static let `default` = LargeTextPolicy(
    largeTextBytes: 64 * 1024,
    extremeTextBytes: 100 * 1024 * 1024,
    excerptLimit: 2_048
  )

  public func classify(text: String) -> LargeTextClassification {
    let bytes = text.utf8.count
    let contentClass = detectContentClass(text)

    guard bytes >= largeTextBytes else {
      return LargeTextClassification(isLarge: false, contentClass: contentClass, metadata: nil)
    }

    let preview = String(text.prefix(excerptLimit))
    let tail = String(text.suffix(excerptLimit))
    let lineEstimate = estimateLineCount(text: text, byteSize: bytes)
    let policy: BlobStoragePolicy = bytes >= extremeTextBytes ? .summaryOnly : .full

    let metadata = LargeTextMetadata(
      byteSize: bytes,
      lineCountEstimate: lineEstimate,
      contentClass: contentClass,
      previewExcerpt: preview,
      tailExcerpt: tail,
      blobStoragePolicy: policy,
      indexingState: .excerptIndexed
    )

    return LargeTextClassification(isLarge: true, contentClass: contentClass, metadata: metadata)
  }

  public func detectContentClass(_ text: String) -> LargeTextContentClass {
    let sample = text.prefix(Self.contentDetectionCharacterLimit)
    let trimmed = sample.drop(while: { $0.isWhitespace })
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
      return .json
    }
    if trimmed.hasPrefix("---") || trimmed.contains(":\n") || trimmed.contains(": ") {
      return .yaml
    }
    if trimmed.contains("\n") && (trimmed.contains("ERROR") || trimmed.contains("INFO") || trimmed.contains("WARN")) {
      return .log
    }
    return .plain
  }

  private func estimateLineCount(text: String, byteSize: Int) -> Int {
    var scannedBytes = 0
    var newlineCount = 0

    for byte in text.utf8.prefix(Self.lineEstimateByteLimit) {
      scannedBytes += 1
      if byte == UInt8(ascii: "\n") {
        newlineCount += 1
      }
    }

    guard scannedBytes > 0 else {
      return 1
    }

    guard scannedBytes < byteSize, newlineCount > 0 else {
      return max(1, newlineCount + 1)
    }

    let estimated = (Double(newlineCount) * Double(byteSize) / Double(scannedBytes)).rounded()
    return max(1, Int(estimated))
  }
}
