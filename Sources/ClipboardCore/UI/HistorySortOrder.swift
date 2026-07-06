/// User-selectable ordering for the QuickPanel history section when no
/// search query is active. Matches Maccy's sort options.
public enum HistorySortOrder: String, CaseIterable, Sendable {
  case lastCopied
  case firstCopied
  case copyCount
}
