import Foundation

public enum BenchmarkComparisonResult: String, Codable, Equatable, Sendable {
  case better
  case same
  case worse
  case notComparable = "not_comparable"
}

public enum BenchmarkComparisonConfidence: String, Codable, Equatable, Sendable {
  case sameMachineBaseline
  case missingBaseline
  case invalidBaseline
}

public struct BenchmarkMetricComparison: Codable, Equatable, Sendable {
  public let name: String
  public let result: BenchmarkComparisonResult
  public let confidence: BenchmarkComparisonConfidence
  public let reason: String
  public let clipboardMedianMs: Double
  public let clipboardP95Ms: Double
  public let maccyMedianMs: Double?
  public let maccyP95Ms: Double?
  public let maccySource: String?

  public init(
    name: String,
    result: BenchmarkComparisonResult,
    confidence: BenchmarkComparisonConfidence,
    reason: String,
    clipboardMedianMs: Double,
    clipboardP95Ms: Double,
    maccyMedianMs: Double?,
    maccyP95Ms: Double?,
    maccySource: String?
  ) {
    self.name = name
    self.result = result
    self.confidence = confidence
    self.reason = reason
    self.clipboardMedianMs = clipboardMedianMs
    self.clipboardP95Ms = clipboardP95Ms
    self.maccyMedianMs = maccyMedianMs
    self.maccyP95Ms = maccyP95Ms
    self.maccySource = maccySource
  }
}

public enum BenchmarkComparison {
  public static func classify(
    clipboardMedian: Double,
    maccyMedian: Double?,
    clipboardP95: Double,
    maccyP95: Double?
  ) -> BenchmarkComparisonResult {
    guard let maccyMedian, let maccyP95, maccyMedian > 0 else {
      return .notComparable
    }

    if clipboardMedian < maccyMedian * 0.8 && clipboardP95 <= maccyP95 {
      return .better
    }

    if clipboardMedian > maccyMedian * 1.2 {
      return .worse
    }

    return .same
  }

  public static func compareMetric(
    name: String,
    clipboardMedian: Double,
    clipboardP95: Double,
    maccyMedian: Double?,
    maccyP95: Double?,
    maccySource: String?
  ) -> BenchmarkMetricComparison {
    guard let maccyMedian, let maccyP95 else {
      return BenchmarkMetricComparison(
        name: name,
        result: .notComparable,
        confidence: .missingBaseline,
        reason: "Maccy baseline is missing for \(name)",
        clipboardMedianMs: clipboardMedian,
        clipboardP95Ms: clipboardP95,
        maccyMedianMs: nil,
        maccyP95Ms: nil,
        maccySource: maccySource
      )
    }

    guard maccyMedian > 0, maccyP95 > 0 else {
      return BenchmarkMetricComparison(
        name: name,
        result: .notComparable,
        confidence: .invalidBaseline,
        reason: "Maccy baseline must have positive median and p95 for \(name)",
        clipboardMedianMs: clipboardMedian,
        clipboardP95Ms: clipboardP95,
        maccyMedianMs: maccyMedian,
        maccyP95Ms: maccyP95,
        maccySource: maccySource
      )
    }

    let result = classify(
      clipboardMedian: clipboardMedian,
      maccyMedian: maccyMedian,
      clipboardP95: clipboardP95,
      maccyP95: maccyP95
    )
    let reason: String = switch result {
    case .better:
      "Clipboard median is at least 20% lower than Maccy and p95 is not worse"
    case .same:
      "Clipboard median is within the 20% same range or p95 prevents a better result"
    case .worse:
      "Clipboard median is more than 20% higher than Maccy"
    case .notComparable:
      "Maccy baseline is not comparable for \(name)"
    }

    return BenchmarkMetricComparison(
      name: name,
      result: result,
      confidence: .sameMachineBaseline,
      reason: reason,
      clipboardMedianMs: clipboardMedian,
      clipboardP95Ms: clipboardP95,
      maccyMedianMs: maccyMedian,
      maccyP95Ms: maccyP95,
      maccySource: maccySource
    )
  }
}
