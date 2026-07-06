import Foundation

/// Result of a fuzzy match. `matchedOffsets` are 0-based Character offsets
/// into the candidate string, used by the UI to highlight hits.
public struct FuzzyMatch: Equatable, Sendable {
  public let score: Int
  public let matchedOffsets: [Int]

  public init(score: Int, matchedOffsets: [Int]) {
    self.score = score
    self.matchedOffsets = matchedOffsets
  }
}

/// Character-based fuzzy matcher. Works on Characters (not scalars) so CJK
/// text matches naturally without any word-boundary concept.
///
/// Scoring tiers:
/// - Full substring hit: top tier (`substringBaseScore` minus a small
///   start-offset penalty) so existing substring-search habits keep ranking first.
/// - In-order subsequence hit: per-character score plus bonuses for
///   consecutive runs and prefix hits. No hit for any query character → nil.
public enum FuzzyMatcher {
  public static let substringBaseScore = 10_000
  public static let subsequenceCharScore = 10
  public static let consecutiveBonus = 15
  public static let prefixBonus = 20

  public static func match(query: String, in candidate: String) -> FuzzyMatch? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !candidate.isEmpty else { return nil }
    let queryChars = Array(trimmed.lowercased())
    let candidateChars = Array(candidate.lowercased())

    if let start = substringStart(of: queryChars, in: candidateChars) {
      let offsets = Array(start..<(start + queryChars.count))
      return FuzzyMatch(score: substringBaseScore - min(start, 100), matchedOffsets: offsets)
    }
    return subsequenceMatch(queryChars, in: candidateChars)
  }

  private static func substringStart(of query: [Character], in candidate: [Character]) -> Int? {
    guard candidate.count >= query.count else { return nil }
    for start in 0...(candidate.count - query.count) {
      var matched = true
      for i in 0..<query.count where candidate[start + i] != query[i] {
        matched = false
        break
      }
      if matched { return start }
    }
    return nil
  }

  private static func subsequenceMatch(_ query: [Character], in candidate: [Character]) -> FuzzyMatch? {
    var offsets: [Int] = []
    var searchIndex = 0
    for ch in query {
      var found: Int?
      var i = searchIndex
      while i < candidate.count {
        if candidate[i] == ch {
          found = i
          break
        }
        i += 1
      }
      guard let hit = found else { return nil }
      offsets.append(hit)
      searchIndex = hit + 1
    }

    var score = offsets.count * subsequenceCharScore
    if offsets.first == 0 {
      score += prefixBonus
    }
    for pair in zip(offsets, offsets.dropFirst()) where pair.1 == pair.0 + 1 {
      score += consecutiveBonus
    }
    return FuzzyMatch(score: score, matchedOffsets: offsets)
  }
}
