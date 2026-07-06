import XCTest
@testable import ClipboardApp

final class QuickPanelHighlightTests: XCTestCase {
    private func emphasizedCharacterOffsets(in attributed: AttributedString) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        var index = attributed.startIndex
        while index < attributed.endIndex {
            let next = attributed.index(afterCharacter: index)
            if attributed[index..<next].inlinePresentationIntent == .stronglyEmphasized {
                offsets.append(offset)
            }
            index = next
            offset += 1
        }
        return offsets
    }

    func testHighlightsExactOffsets() {
        let result = QuickPanelHighlight.attributed(text: "clipboard", highlightOffsets: [4, 5, 6])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [4, 5, 6])
        XCTAssertEqual(String(result.characters), "clipboard")
    }

    func testEmptyOffsetsProducePlainText() {
        let result = QuickPanelHighlight.attributed(text: "clipboard", highlightOffsets: [])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [])
    }

    func testOutOfRangeOffsetsAreIgnored() {
        let result = QuickPanelHighlight.attributed(text: "abc", highlightOffsets: [-1, 2, 99])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [2])
    }

    func testCJKOffsetsHighlightWholeCharacters() {
        let result = QuickPanelHighlight.attributed(text: "剪贴板历史", highlightOffsets: [0, 2])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [0, 2])
    }
}
