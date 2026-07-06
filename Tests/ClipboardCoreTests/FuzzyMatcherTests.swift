import XCTest
@testable import ClipboardCore

final class FuzzyMatcherTests: XCTestCase {
    func testSubstringMatchReturnsContiguousOffsets() {
        let match = FuzzyMatcher.match(query: "board", in: "clipboard manager")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchedOffsets, [4, 5, 6, 7, 8])
    }

    func testSubstringMatchIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "BOARD", in: "Clipboard"))
    }

    func testSubstringScoreBeatsAnySubsequenceScore() {
        let substring = FuzzyMatcher.match(query: "clip", in: "clipboard")!
        let subsequence = FuzzyMatcher.match(query: "cb", in: "clipboard")!
        XCTAssertGreaterThan(substring.score, subsequence.score)
    }

    func testSubsequenceMatchFindsNonContiguousCharacters() {
        let match = FuzzyMatcher.match(query: "cbm", in: "clipboard manager")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchedOffsets, [0, 4, 10])
    }

    func testConsecutiveHitsScoreHigherThanScatteredHits() {
        // "ab" in "xabx" is consecutive; "ab" in "xaxb" is scattered.
        let consecutive = FuzzyMatcher.match(query: "ab", in: "xabx")!
        let scattered = FuzzyMatcher.match(query: "ab", in: "xaxb")!
        XCTAssertGreaterThan(consecutive.score, scattered.score)
    }

    func testCJKSubsequenceMatches() {
        let match = FuzzyMatcher.match(query: "剪板", in: "剪贴板历史")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchedOffsets, [0, 2])
    }

    func testCJKSubstringMatches() {
        let match = FuzzyMatcher.match(query: "剪贴板", in: "系统剪贴板历史")
        XCTAssertEqual(match?.matchedOffsets, [2, 3, 4])
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "zzz", in: "clipboard"))
    }

    func testMissingOneCharacterReturnsNil() {
        // All query characters must be present in order.
        XCTAssertNil(FuzzyMatcher.match(query: "cbz", in: "clipboard"))
    }

    func testEmptyOrWhitespaceQueryReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "", in: "clipboard"))
        XCTAssertNil(FuzzyMatcher.match(query: "   ", in: "clipboard"))
    }

    func testEmptyCandidateReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "a", in: ""))
    }

    func testLongSubsequenceNeverOutranksSubstring() {
        // A near-contiguous 500-char subsequence (broken once in the middle)
        // must still score strictly below any full substring hit, even one
        // starting at a heavily penalized offset.
        let query = String(repeating: "a", count: 500)
        let subsequenceCandidate =
            String(repeating: "a", count: 250) + "b" + String(repeating: "a", count: 250)
        let substringCandidate = String(repeating: "x", count: 120) + query

        let subsequence = FuzzyMatcher.match(query: query, in: subsequenceCandidate)!
        let substring = FuzzyMatcher.match(query: query, in: substringCandidate)!

        XCTAssertGreaterThan(substring.score, subsequence.score)
        XCTAssertLessThan(subsequence.score, FuzzyMatcher.substringBaseScore - 100)
    }

    func testEarlierSubstringStartScoresHigher() {
        let early = FuzzyMatcher.match(query: "clip", in: "clipboard")!
        let late = FuzzyMatcher.match(query: "clip", in: "my clipboard")!
        XCTAssertGreaterThan(early.score, late.score)
    }
}
