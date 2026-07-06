import AppKit
import ClipboardCore
import Combine
import Foundation

enum QuickPanelContentFilter: String, CaseIterable, Identifiable {
  case all
  case text
  case link
  case image
  case file

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "All"
    case .text: return "Text"
    case .link: return "Link"
    case .image: return "Image"
    case .file: return "File"
    }
  }

  var contentTypes: Set<ClipboardContentType> {
    switch self {
    case .all:
      return []
    case .text:
      return [.text, .richText]
    case .link:
      return [.link]
    case .image:
      return [.image]
    case .file:
      return [.file]
    }
  }

  func advanced(by delta: Int) -> QuickPanelContentFilter {
    let filters = Self.allCases
    guard let currentIndex = filters.firstIndex(of: self), !filters.isEmpty else {
      return self
    }

    let count = filters.count
    let nextIndex = ((currentIndex + delta) % count + count) % count
    return filters[nextIndex]
  }
}

enum QuickPanelActionPrompt: Equatable {
  case autoPasteRequiresAccessibilityPermission
}

struct QuickPanelRowShortcut: Equatable {
  let label: String
  let accessibilityLabel: String

  static func historyNumber(_ number: Int) -> QuickPanelRowShortcut {
    QuickPanelRowShortcut(label: "\(number)", accessibilityLabel: "Shortcut \(number)")
  }

  static func pinnedLetter(_ letter: String) -> QuickPanelRowShortcut {
    QuickPanelRowShortcut(label: "⌘\(letter)", accessibilityLabel: "Shortcut Command \(letter)")
  }
}

struct QuickPanelItemRow: Identifiable, Equatable {
  let index: Int
  let record: ClipboardRecord
  let shortcut: QuickPanelRowShortcut?

  var id: UUID { record.id }
}

struct QuickPanelPlainTextPasteRequest {
  let record: ClipboardRecord
  let plainText: String
}

struct QuickPanelItemSection: Identifiable, Equatable {
  enum Kind: String {
    case pinned
    case history
  }

  static let pinnedShortcutLetters = ["A", "S", "D", "F", "G", "H", "J", "K", "L"]

  let kind: Kind
  let title: String
  let rows: [QuickPanelItemRow]

  var id: Kind { kind }

  static func make(from items: [ClipboardRecord]) -> [QuickPanelItemSection] {
    let indexedItems = items.enumerated().map { index, record in
      (index: index, record: record)
    }
    let pinnedItems = indexedItems.filter { $0.record.isPinned }
    let historyItems = indexedItems.filter { !$0.record.isPinned }

    let pinnedRows = pinnedItems.enumerated().map { localIndex, item in
      QuickPanelItemRow(
        index: item.index,
        record: item.record,
        shortcut: pinnedShortcutLetters.indices.contains(localIndex)
          ? .pinnedLetter(pinnedShortcutLetters[localIndex])
          : nil
      )
    }
    let historyRows = historyItems.enumerated().map { localIndex, item in
      QuickPanelItemRow(
        index: item.index,
        record: item.record,
        shortcut: localIndex < 9 ? .historyNumber(localIndex + 1) : nil
      )
    }

    var sections: [QuickPanelItemSection] = []
    if !pinnedRows.isEmpty {
      sections.append(QuickPanelItemSection(kind: .pinned, title: "Pinned", rows: pinnedRows))
    }
    if !historyRows.isEmpty {
      sections.append(QuickPanelItemSection(kind: .history, title: "History", rows: historyRows))
    }
    return sections
  }
}

struct QuickPanelItemRenderIdentity: Hashable {
  let recordID: UUID
  let isPinned: Bool

  static func make(from items: [ClipboardRecord]) -> [QuickPanelItemRenderIdentity] {
    items.map { record in
      QuickPanelItemRenderIdentity(recordID: record.id, isPinned: record.isPinned)
    }
  }
}

struct QuickPanelDetailPreview: Identifiable, Equatable {
  let id: UUID
  let title: String
  let source: String
  let body: String
  let isTruncated: Bool
  /// Decoded image to render in the preview. When non-nil the preview shows the
  /// image itself instead of `body`; `body` carries the text fallback otherwise.
  let image: NSImage?

  static func == (lhs: QuickPanelDetailPreview, rhs: QuickPanelDetailPreview) -> Bool {
    lhs.id == rhs.id
      && lhs.title == rhs.title
      && lhs.source == rhs.source
      && lhs.body == rhs.body
      && lhs.isTruncated == rhs.isTruncated
      && lhs.image === rhs.image
  }
}

@MainActor
final class QuickPanelState: ObservableObject {
  @Published private(set) var query = ""
  @Published private(set) var contentFilter: QuickPanelContentFilter = .all
  @Published private(set) var items: [ClipboardRecord] = []
  @Published private(set) var matchOffsets: [UUID: [Int]] = [:]
  @Published private(set) var selectedIndex = 0
  @Published private(set) var footerStatus = "Ready"
  @Published private(set) var actionPrompt: QuickPanelActionPrompt?
  @Published private(set) var detailPreview: QuickPanelDetailPreview?
  @Published private(set) var presentationGeneration = 0

  private let viewModel: QuickPanelViewModel
  private let payloadStore: any ClipboardPayloadStore
  private let pasteController: PasteController
  private let mutationService: HistoryMutationService
  private var refreshTask: Task<Bool, Never>?
  private var refreshGeneration = 0
  private var detailPreviewGeneration = 0
  private var latestAppliedQuery = ""
  private var latestAppliedContentFilter: QuickPanelContentFilter = .all
  private var selectedRecordID: UUID?
  private var footerStatusSource: FooterStatusSource = .refresh
  private var pendingOpenSelectionBehavior: QuickPanelOpenSelectionBehavior?
  private var suppressedShortcutInsertedText: String?

  init(
    viewModel: QuickPanelViewModel,
    payloadStore: any ClipboardPayloadStore,
    pasteController: PasteController,
    mutationService: HistoryMutationService
  ) {
    self.viewModel = viewModel
    self.payloadStore = payloadStore
    self.pasteController = pasteController
    self.mutationService = mutationService
  }

  func updateQuery(_ query: String) {
    guard self.query != query else {
      return
    }

    if shouldSuppressShortcutQueryMutation(query) {
      return
    }

    self.query = query
    footerStatusSource = .refresh
    actionPrompt = nil
    scheduleRefresh()
  }

  func suppressNextShortcutQueryMutation(insertedText: String) {
    suppressedShortcutInsertedText = insertedText
  }

  func updateContentFilter(_ filter: QuickPanelContentFilter) {
    guard contentFilter != filter else {
      return
    }

    contentFilter = filter
    footerStatusSource = .refresh
    actionPrompt = nil
    scheduleRefresh()
  }

  func cycleContentFilter(delta: Int) {
    updateContentFilter(contentFilter.advanced(by: delta))
  }

  func prepareForPresentation(openSelectionBehavior: QuickPanelOpenSelectionBehavior = .latestRecord) {
    presentationGeneration += 1
    footerStatusSource = .refresh
    footerStatus = "Ready"
    actionPrompt = nil
    pendingOpenSelectionBehavior = openSelectionBehavior
    if openSelectionBehavior == .latestRecord {
      selectedIndex = defaultSelectionIndex(in: items)
      selectedRecordID = nil
    }
  }

  func refresh() async {
    repeat {
      let task = scheduleRefresh()
      _ = await task.value
    } while (latestAppliedQuery != query || latestAppliedContentFilter != contentFilter) && !Task.isCancelled
  }

  private func refreshForUserAction() async {
    repeat {
      refreshGeneration += 1
      let generation = refreshGeneration
      let querySnapshot = query
      let filterSnapshot = contentFilter
      refreshTask?.cancel()
      let didApply = await applyRefresh(
        querySnapshot: querySnapshot,
        filterSnapshot: filterSnapshot,
        generation: generation,
        requireCurrentGeneration: false
      )
      if didApply {
        return
      }
    } while !Task.isCancelled
  }

  var itemSections: [QuickPanelItemSection] {
    QuickPanelItemSection.make(from: items)
  }

  var itemRenderIdentities: [QuickPanelItemRenderIdentity] {
    QuickPanelItemRenderIdentity.make(from: items)
  }

  func moveSelection(delta: Int) {
    Task {
      await viewModel.moveSelection(delta: delta)
      selectedIndex = await viewModel.selectedIndex
      selectedRecordID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
    }
  }

  func selectItem(at index: Int) {
    guard items.indices.contains(index) else {
      return
    }
    selectedIndex = index
    selectedRecordID = items[index].id
    Task {
      await viewModel.setSelection(index: index)
    }
  }

  func selectHistoryShortcut(number: Int) async {
    await refreshForShortcutIfNeeded()

    guard let index = historyShortcutIndex(number: number) else {
      return
    }
    selectItem(at: index)
  }

  func selectPinnedShortcut(slot: Int) async {
    await refreshForShortcutIfNeeded()

    guard let index = pinnedShortcutIndex(slot: slot) else {
      return
    }
    selectItem(at: index)
  }

  func prepareHistoryShortcutPaste(number: Int) async -> Bool {
    await refreshForShortcutIfNeeded()

    guard let index = historyShortcutIndex(number: number) else {
      return false
    }

    selectItem(at: index)
    return true
  }

  func reportAutoPasteRequiresAccessibilityPermission() {
    actionPrompt = .autoPasteRequiresAccessibilityPermission
    setUserActionFooterStatus("自动粘贴需要辅助功能权限，请在设置中授权")
  }

  func dismissActionPrompt() {
    actionPrompt = nil
  }

  func reportCopyOnlyModeEnabled() {
    actionPrompt = nil
    setUserActionFooterStatus("已改为仅复制模式")
  }

  func selectCurrent(autoPaste: Bool) async {
    guard let (record, payload) = await currentRecordAndPayloadAfterRefresh() else {
      return
    }

    let transaction = await pasteController.paste(
      record: record,
      payload: payload,
      autoPaste: autoPaste
    )

    setPasteTransactionFooterStatus(
      transaction,
      successStatus: autoPaste ? "Pasted \(record.primaryType.rawValue)" : "Copied \(record.primaryType.rawValue)"
    )
  }

  func pasteHistoryShortcut(number: Int) async {
    guard await prepareHistoryShortcutPaste(number: number) else {
      return
    }

    await selectCurrent(autoPaste: true)
  }

  func pastePlainText() async {
    guard let request = await preparePlainTextPaste() else {
      return
    }

    await pastePlainText(request)
  }

  func preparePlainTextPaste() async -> QuickPanelPlainTextPasteRequest? {
    guard let (record, payload) = await currentRecordAndPayloadForUserAction() else {
      return nil
    }

    guard let plainText = payload.plainTextForPaste else {
      setUserActionFooterStatus("Plain text paste is not supported for \(record.primaryType.rawValue)")
      return nil
    }

    return QuickPanelPlainTextPasteRequest(record: record, plainText: plainText)
  }

  func pastePlainText(_ request: QuickPanelPlainTextPasteRequest) async {
    let transaction = await pasteController.paste(
      record: request.record,
      payload: .text(request.plainText),
      autoPaste: true
    )

    setPasteTransactionFooterStatus(transaction, successStatus: "Pasted plain text")
  }

  func imagePreview(for record: ClipboardRecord) async -> NSImage? {
    guard record.primaryType == .image,
          case let .image(data, _) = try? await payloadStore.loadPayload(for: record.id) else {
      return nil
    }

    return NSImage(data: data)
  }

  func showDetailPreview() async {
    detailPreviewGeneration += 1
    let generation = detailPreviewGeneration

    guard let recordID = currentRecordID,
          let record = items.first(where: { $0.id == recordID }) else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      guard isCurrentDetailPreviewRequest(generation: generation, recordID: recordID) else {
        return
      }
      setUserActionFooterStatus("Payload is unavailable in this session")
      return
    }

    guard isCurrentDetailPreviewRequest(generation: generation, recordID: recordID) else {
      return
    }

    let source = QuickPanelRowPresentation.sourceName(for: record)

    if case let .image(data, _) = payload, let image = NSImage(data: data) {
      detailPreview = QuickPanelDetailPreview(
        id: record.id,
        title: record.title,
        source: source,
        body: "",
        isTruncated: false,
        image: image
      )
      return
    }

    let body = detailBody(for: payload, fallback: record.plainTextPreview ?? record.title)
    detailPreview = QuickPanelDetailPreview(
      id: record.id,
      title: record.title,
      source: source,
      body: body.text,
      isTruncated: body.isTruncated,
      image: nil
    )
  }

  func dismissDetailPreview() {
    detailPreviewGeneration += 1
    detailPreview = nil
  }

  func deleteSelected() async {
    guard let recordID = currentRecordID else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    do {
      try await mutationService.deleteRecord(id: recordID)
      selectedRecordID = nil
      setUserActionFooterStatus("Deleted 1 item")
      await refresh()
    } catch {
      setUserActionFooterStatus("Delete failed: \(error.localizedDescription)")
    }
  }

  func togglePinned() async {
    guard let recordID = currentRecordID else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    do {
      let updated = try await mutationService.togglePinned(id: recordID)
      selectedRecordID = updated.id
      setUserActionFooterStatus(updated.isPinned ? "Pinned item" : "Unpinned item")
      await refresh()
    } catch {
      setUserActionFooterStatus("Pin failed: \(error.localizedDescription)")
    }
  }

  func clearUnpinned() async {
    do {
      let count = try await mutationService.clearUnpinned()
      selectedRecordID = nil
      setUserActionFooterStatus("Cleared \(count) unpinned item\(count == 1 ? "" : "s")")
      await refresh()
    } catch {
      setUserActionFooterStatus("Clear failed: \(error.localizedDescription)")
    }
  }

  func clearAll() async {
    do {
      let count = try await mutationService.clearAll()
      selectedRecordID = nil
      setUserActionFooterStatus("Cleared \(count) item\(count == 1 ? "" : "s")")
      await refresh()
    } catch {
      setUserActionFooterStatus("Clear failed: \(error.localizedDescription)")
    }
  }

  private var currentRecordID: UUID? {
    selectedRecordID ?? (items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil)
  }

  private func refreshForShortcutIfNeeded() async {
    if items.isEmpty || latestAppliedQuery != query || latestAppliedContentFilter != contentFilter {
      await refreshForUserAction()
    }
  }

  private func historyShortcutIndex(number: Int) -> Int? {
    guard (1...9).contains(number) else {
      return nil
    }
    let historyRows = itemSections.first { $0.kind == .history }?.rows ?? []
    let localIndex = number - 1
    guard historyRows.indices.contains(localIndex) else {
      return nil
    }
    return historyRows[localIndex].index
  }

  private func pinnedShortcutIndex(slot: Int) -> Int? {
    guard QuickPanelItemSection.pinnedShortcutLetters.indices.contains(slot) else {
      return nil
    }
    let pinnedRows = itemSections.first { $0.kind == .pinned }?.rows ?? []
    guard pinnedRows.indices.contains(slot) else {
      return nil
    }
    return pinnedRows[slot].index
  }

  private func defaultSelectionIndex(in records: [ClipboardRecord]) -> Int {
    records.firstIndex { !$0.isPinned } ?? (records.isEmpty ? 0 : 0)
  }

  private func currentRecordAndPayloadForUserAction() async -> (record: ClipboardRecord, payload: ClipboardPayload)? {
    let selectionQuery = query
    if latestAppliedQuery == query,
       latestAppliedContentFilter == contentFilter,
       let record = currentVisibleRecord() {
      guard let payload = await loadPayloadForUserAction(record: record) else {
        return nil
      }
      return (record, payload)
    }

    await refreshForUserAction()

    guard selectionQuery == query else {
      await refreshForUserAction()
      setUserActionFooterStatus("Selection changed")
      return nil
    }

    guard let record = currentVisibleRecord() else {
      setUserActionFooterStatus("No clipboard item selected")
      return nil
    }

    guard let payload = await loadPayloadForUserAction(record: record) else {
      return nil
    }

    return (record, payload)
  }

  private func currentVisibleRecord() -> ClipboardRecord? {
    guard let recordID = currentRecordID,
          let record = items.first(where: { $0.id == recordID }) else {
      return nil
    }

    return record
  }

  private func loadPayloadForUserAction(record: ClipboardRecord) async -> ClipboardPayload? {
    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      setUserActionFooterStatus("Payload is unavailable in this session")
      return nil
    }

    return payload
  }

  private func currentRecordAndPayloadAfterRefresh() async -> (record: ClipboardRecord, payload: ClipboardPayload)? {
    let selectionQuery = query
    let recordID = currentRecordID
    await refresh()

    guard selectionQuery == query else {
      await refresh()
      setUserActionFooterStatus("Selection changed")
      return nil
    }

    guard let recordID else {
      setUserActionFooterStatus("No clipboard item selected")
      return nil
    }

    guard let record = items.first(where: { $0.id == recordID }) else {
      setUserActionFooterStatus("Selected item is no longer visible")
      return nil
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      setUserActionFooterStatus("Payload is unavailable in this session")
      return nil
    }

    return (record, payload)
  }

  private func isCurrentDetailPreviewRequest(generation: Int, recordID: UUID) -> Bool {
    generation == detailPreviewGeneration && currentRecordID == recordID
  }

  private func detailBody(for payload: ClipboardPayload, fallback: String) -> (text: String, isTruncated: Bool) {
    let rawText: String = switch payload {
    case .text(let text):
      text
    case .richText(let plainText, _, _):
      plainText
    case .image:
      fallback.isEmpty ? "Image preview is available in the row." : fallback
    case .fileURLs(let urls):
      urls.map(\.path).joined(separator: "\n")
    }

    let limit = 20_000
    guard rawText.count > limit else {
      return (rawText, false)
    }
    return (String(rawText.prefix(limit)), true)
  }

  private func setPasteTransactionFooterStatus(_ transaction: PasteTransaction, successStatus: String) {
    switch transaction.state {
    case .completed:
      actionPrompt = nil
      setUserActionFooterStatus(successStatus)
    case let .failed(reason):
      setUserActionFooterStatus("Paste failed: \(reason.rawValue)")
    default:
      setUserActionFooterStatus("Paste transaction ended in \(transaction.state)")
    }
  }

  @discardableResult
  private func scheduleRefresh() -> Task<Bool, Never> {
    refreshGeneration += 1
    let generation = refreshGeneration
    let querySnapshot = query
    let filterSnapshot = contentFilter
    refreshTask?.cancel()

    let task = Task { [weak self] in
      guard let self else {
        return false
      }
      return await self.applyRefresh(querySnapshot: querySnapshot, filterSnapshot: filterSnapshot, generation: generation)
    }
    refreshTask = task
    return task
  }

  private func applyRefresh(
    querySnapshot: String,
    filterSnapshot: QuickPanelContentFilter,
    generation: Int,
    requireCurrentGeneration: Bool = true
  ) async -> Bool {
    let didRefreshViewModel = await viewModel.refresh(query: querySnapshot, contentTypes: filterSnapshot.contentTypes)
    guard didRefreshViewModel else {
      return false
    }

    guard !Task.isCancelled else {
      return false
    }

    guard !Task.isCancelled,
          (!requireCurrentGeneration || generation == refreshGeneration),
          querySnapshot == query,
          filterSnapshot == contentFilter else {
      return false
    }

    let selectionRecordID = selectedRecordID
    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex: Int
    if pendingOpenSelectionBehavior == .latestRecord {
      refreshedSelectedIndex = defaultSelectionIndex(in: refreshedItems)
      await viewModel.setSelection(index: refreshedSelectedIndex)
    } else if let selectionRecordID,
              let matchingIndex = refreshedItems.firstIndex(where: { $0.id == selectionRecordID }) {
      refreshedSelectedIndex = matchingIndex
      await viewModel.setSelection(index: matchingIndex)
    } else if selectionRecordID != nil {
      refreshedSelectedIndex = defaultSelectionIndex(in: refreshedItems)
      await viewModel.setSelection(index: refreshedSelectedIndex)
    } else {
      refreshedSelectedIndex = await viewModel.selectedIndex
    }

    items = refreshedItems
    matchOffsets = await viewModel.searchMatches.mapValues(\.primaryTextOffsets)
    selectedIndex = refreshedSelectedIndex
    selectedRecordID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
    pendingOpenSelectionBehavior = nil
    if footerStatusSource == .refresh {
      footerStatus = items.isEmpty ? "No matching clipboard items" : "\(items.count) item\(items.count == 1 ? "" : "s")"
    }
    latestAppliedQuery = querySnapshot
    latestAppliedContentFilter = filterSnapshot
    return true
  }

  private func setUserActionFooterStatus(_ status: String) {
    footerStatusSource = .userAction
    footerStatus = status
  }

  private func shouldSuppressShortcutQueryMutation(_ newQuery: String) -> Bool {
    guard let insertedText = suppressedShortcutInsertedText else {
      return false
    }
    suppressedShortcutInsertedText = nil
    return newQuery == insertedText || newQuery == query + insertedText
  }
}

private enum FooterStatusSource {
  case refresh
  case userAction
}
