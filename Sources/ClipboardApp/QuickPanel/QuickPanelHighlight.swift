import SwiftUI

/// Builds the highlighted primary-content text for a QuickPanel row.
/// Offsets are 0-based Character offsets produced by FuzzyMatcher against
/// the same string; out-of-range offsets are ignored defensively because
/// the displayed text and the matched text are derived independently.
enum QuickPanelHighlight {
    static func attributed(text: String, highlightOffsets: [Int]) -> AttributedString {
        var result = AttributedString(text)
        guard !highlightOffsets.isEmpty else { return result }

        let characterCount = text.count
        let valid = Set(highlightOffsets.filter { $0 >= 0 && $0 < characterCount })
        guard !valid.isEmpty else { return result }

        var offset = 0
        var index = result.startIndex
        while index < result.endIndex {
            let next = result.index(afterCharacter: index)
            if valid.contains(offset) {
                result[index..<next].inlinePresentationIntent = .stronglyEmphasized
                result[index..<next].foregroundColor = Color.accentColor
            }
            index = next
            offset += 1
        }
        return result
    }
}
