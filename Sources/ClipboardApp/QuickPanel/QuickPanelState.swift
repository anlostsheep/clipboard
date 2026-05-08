import AppKit
import ClipboardCore
import Combine
import Foundation

@MainActor
final class QuickPanelState: ObservableObject {
  @Published private(set) var query = ""
  @Published private(set) var items: [ClipboardRecord] = []
  @Published private(set) var selectedIndex = 0
  @Published private(set) var footerStatus = "Ready"

  private let viewModel: QuickPanelViewModel
  private let payloadStore: InMemoryPayloadStore
  private let pasteController: PasteController
  private var refreshTask: Task<Void, Never>?
  private var refreshGeneration = 0
  private var latestAppliedQuery = ""

  init(
    viewModel: QuickPanelViewModel,
    payloadStore: InMemoryPayloadStore,
    pasteController: PasteController
  ) {
    self.viewModel = viewModel
    self.payloadStore = payloadStore
    self.pasteController = pasteController
  }

  func updateQuery(_ query: String) {
    self.query = query
    scheduleRefresh()
  }

  func refresh() async {
    repeat {
      let task = scheduleRefresh()
      await task.value
    } while latestAppliedQuery != query && !Task.isCancelled
  }

  func moveSelection(delta: Int) {
    Task {
      await viewModel.moveSelection(delta: delta)
      selectedIndex = await viewModel.selectedIndex
    }
  }

  func selectCurrent(autoPaste: Bool) async {
    await refresh()
    let selectionQuery = query

    guard items.indices.contains(selectedIndex) else {
      footerStatus = "No clipboard item selected"
      return
    }

    let selectedRecord = items[selectedIndex]

    guard let intent = await viewModel.selectedIntent(autoPaste: autoPaste) else {
      footerStatus = "No clipboard item selected"
      return
    }

    guard selectionQuery == query, intent.recordID == selectedRecord.id else {
      await refresh()
      footerStatus = "Selection changed"
      return
    }

    guard let record = items.first(where: { $0.id == intent.recordID }) else {
      footerStatus = "Selected item is no longer visible"
      return
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      footerStatus = "Payload is unavailable in this session"
      return
    }

    let transaction = await pasteController.paste(
      record: record,
      payload: payload,
      autoPaste: intent.autoPaste
    )

    switch transaction.state {
    case .completed:
      footerStatus = intent.autoPaste ? "Pasted \(record.primaryType.rawValue)" : "Copied \(record.primaryType.rawValue)"
    case let .failed(reason):
      footerStatus = "Paste failed: \(reason.rawValue)"
    default:
      footerStatus = "Paste transaction ended in \(transaction.state)"
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
    refreshTask?.cancel()

    let task = Task { [weak self] in
      guard let self else {
        return
      }
      await self.applyRefresh(querySnapshot: querySnapshot, generation: generation)
    }
    refreshTask = task
    return task
  }

  private func applyRefresh(querySnapshot: String, generation: Int) async {
    await viewModel.refresh(query: querySnapshot)

    guard !Task.isCancelled else {
      return
    }

    let refreshedItems = await viewModel.items
    let refreshedSelectedIndex = await viewModel.selectedIndex

    guard !Task.isCancelled, generation == refreshGeneration, querySnapshot == query else {
      return
    }

    items = refreshedItems
    selectedIndex = refreshedSelectedIndex
    footerStatus = items.isEmpty ? "No matching clipboard items" : "\(items.count) item\(items.count == 1 ? "" : "s")"
    latestAppliedQuery = querySnapshot
  }
}
