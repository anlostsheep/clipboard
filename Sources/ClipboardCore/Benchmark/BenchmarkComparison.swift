import Foundation

public enum BenchmarkComparisonResult: String, Codable, Equatable, Sendable {
  case better
  case same
  case worse
  case notComparable = "not_comparable"
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
}
