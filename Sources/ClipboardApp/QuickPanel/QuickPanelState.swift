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
}

enum QuickPanelActionPrompt: Equatable {
  case autoPasteRequiresAccessibilityPermission
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
  private var refreshTask: Task<Void, Never>?
  private var refreshGeneration = 0
  private var latestAppliedQuery = ""
  private var latestAppliedContentFilter: QuickPanelContentFilter = .all
  private var selectedRecordID: UUID?
  private var footerStatusSource: FooterStatusSource = .refresh
  private var pendingOpenSelectionBehavior: QuickPanelOpenSelectionBehavior?

  init(
    viewModel: QuickPanelViewModel,
    payloadStore: any ClipboardPayloadStore,
    pasteController: PasteController
  ) {
    self.viewModel = viewModel
    self.payloadStore = payloadStore
    self.pasteController = pasteController
  }

  func updateQuery(_ query: String) {
    guard self.query != query else {
      return
    }

    self.query = query
    footerStatusSource = .refresh
    actionPrompt = nil
    scheduleRefresh()
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
    let recordID = selectedRecordID ?? (items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil)
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

  func imagePreview(for record: ClipboardRecord) async -> NSImage? {
    guard record.primaryType == .image,
          case let .image(data, _) = try? await payloadStore.loadPayload(for: record.id) else {
      return nil
    }

    return NSImage(data: data)
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

    if pendingOpenSelectionBehavior == .latestRecord {
      await viewModel.setSelection(index: 0)
    }

    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex = await viewModel.selectedIndex

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
}

private enum FooterStatusSource {
  case refresh
  case userAction
}
