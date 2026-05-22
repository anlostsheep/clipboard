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

struct QuickPanelItemRow: Identifiable, Equatable {
  let index: Int
  let record: ClipboardRecord

  var id: UUID { record.id }
}

struct QuickPanelItemSection: Identifiable, Equatable {
  enum Kind: String {
    case pinned
    case history
  }

  let kind: Kind
  let title: String
  let rows: [QuickPanelItemRow]

  var id: Kind { kind }

  static func make(from items: [ClipboardRecord]) -> [QuickPanelItemSection] {
    let rows = items.enumerated().map { index, record in
      QuickPanelItemRow(index: index, record: record)
    }
    let pinnedRows = rows.filter { $0.record.isPinned }
    let historyRows = rows.filter { !$0.record.isPinned }

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

@MainActor
final class QuickPanelState: ObservableObject {
  @Published private(set) var query = ""
  @Published private(set) var contentFilter: QuickPanelContentFilter = .all
  @Published private(set) var items: [ClipboardRecord] = []
  @Published private(set) var selectedIndex = 0
  @Published private(set) var footerStatus = "Ready"
  @Published private(set) var actionPrompt: QuickPanelActionPrompt?

  private let viewModel: QuickPanelViewModel
  private let payloadStore: any ClipboardPayloadStore
  private let pasteController: PasteController
  private let mutationService: HistoryMutationService
  private var refreshTask: Task<Void, Never>?
  private var refreshGeneration = 0
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
    footerStatusSource = .refresh
    footerStatus = "Ready"
    actionPrompt = nil
    pendingOpenSelectionBehavior = openSelectionBehavior
    if openSelectionBehavior == .latestRecord {
      selectedIndex = 0
      selectedRecordID = items.first?.id
    }
  }

  func refresh() async {
    repeat {
      let task = scheduleRefresh()
      await task.value
    } while (latestAppliedQuery != query || latestAppliedContentFilter != contentFilter) && !Task.isCancelled
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

  func selectVisibleItem(number: Int) {
    let index = number - 1
    selectItem(at: index)
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
    let selectionQuery = query
    let recordID = currentRecordID
    await refresh()

    guard selectionQuery == query else {
      await refresh()
      setUserActionFooterStatus("Selection changed")
      return
    }

    guard let recordID else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    guard let record = items.first(where: { $0.id == recordID }) else {
      setUserActionFooterStatus("Selected item is no longer visible")
      return
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      setUserActionFooterStatus("Payload is unavailable in this session")
      return
    }

    let transaction = await pasteController.paste(
      record: record,
      payload: payload,
      autoPaste: autoPaste
    )

    switch transaction.state {
    case .completed:
      actionPrompt = nil
      setUserActionFooterStatus(autoPaste ? "Pasted \(record.primaryType.rawValue)" : "Copied \(record.primaryType.rawValue)")
    case let .failed(reason):
      setUserActionFooterStatus("Paste failed: \(reason.rawValue)")
    default:
      setUserActionFooterStatus("Paste transaction ended in \(transaction.state)")
    }
  }

  func pasteVisibleItem(number: Int) async {
    let index = number - 1
    guard items.indices.contains(index) else {
      return
    }

    selectItem(at: index)
    await selectCurrent(autoPaste: true)
  }

  func pastePlainText() async {
    let selectionQuery = query
    let recordID = currentRecordID
    await refresh()

    guard selectionQuery == query else {
      await refresh()
      setUserActionFooterStatus("Selection changed")
      return
    }

    guard let recordID else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    guard let record = items.first(where: { $0.id == recordID }) else {
      setUserActionFooterStatus("Selected item is no longer visible")
      return
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      setUserActionFooterStatus("Payload is unavailable in this session")
      return
    }

    guard let plainText = payload.plainTextForPaste else {
      setUserActionFooterStatus("Plain text paste is not supported for \(record.primaryType.rawValue)")
      return
    }

    let transaction = await pasteController.paste(
      record: record,
      payload: .text(plainText),
      autoPaste: true
    )

    switch transaction.state {
    case .completed:
      actionPrompt = nil
      setUserActionFooterStatus("Pasted plain text")
    case let .failed(reason):
      setUserActionFooterStatus("Paste failed: \(reason.rawValue)")
    default:
      setUserActionFooterStatus("Paste transaction ended in \(transaction.state)")
    }
  }

  func imagePreview(for record: ClipboardRecord) async -> NSImage? {
    guard record.primaryType == .image,
          case let .image(data, _) = try? await payloadStore.loadPayload(for: record.id) else {
      return nil
    }

    return NSImage(data: data)
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

  @discardableResult
  private func scheduleRefresh() -> Task<Void, Never> {
    refreshGeneration += 1
    let generation = refreshGeneration
    let querySnapshot = query
    let filterSnapshot = contentFilter
    refreshTask?.cancel()

    let task = Task { [weak self] in
      guard let self else {
        return
      }
      await self.applyRefresh(querySnapshot: querySnapshot, filterSnapshot: filterSnapshot, generation: generation)
    }
    refreshTask = task
    return task
  }

  private func applyRefresh(
    querySnapshot: String,
    filterSnapshot: QuickPanelContentFilter,
    generation: Int
  ) async {
    await viewModel.refresh(query: querySnapshot, contentTypes: filterSnapshot.contentTypes)

    guard !Task.isCancelled else {
      return
    }

    guard !Task.isCancelled,
          generation == refreshGeneration,
          querySnapshot == query,
          filterSnapshot == contentFilter else {
      return
    }

    let selectionRecordID = selectedRecordID
    if pendingOpenSelectionBehavior == .latestRecord {
      await viewModel.setSelection(index: 0)
    }

    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex: Int
    if let selectionRecordID,
       let matchingIndex = refreshedItems.firstIndex(where: { $0.id == selectionRecordID }) {
      refreshedSelectedIndex = matchingIndex
      await viewModel.setSelection(index: matchingIndex)
    } else if selectionRecordID != nil {
      refreshedSelectedIndex = 0
      await viewModel.setSelection(index: 0)
    } else {
      refreshedSelectedIndex = await viewModel.selectedIndex
    }

    items = refreshedItems
    selectedIndex = refreshedSelectedIndex
    selectedRecordID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
    pendingOpenSelectionBehavior = nil
    if footerStatusSource == .refresh {
      footerStatus = items.isEmpty ? "No matching clipboard items" : "\(items.count) item\(items.count == 1 ? "" : "s")"
    }
    latestAppliedQuery = querySnapshot
    latestAppliedContentFilter = filterSnapshot
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
