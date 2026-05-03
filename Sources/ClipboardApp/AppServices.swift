import ClipboardCore
import ClipboardPlatform
import Foundation

@MainActor
final class AppServices {
  let store: InMemoryHistoryStore
  let payloadStore: InMemoryPayloadStore
  let systemClient: SystemPasteboardClient
  let ingestService: ClipboardIngestService
  let monitor: ClipboardMonitor
  let pasteController: PasteController
  lazy var quickPanelState = QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 50),
    payloadStore: payloadStore,
    pasteController: pasteController
  )
  lazy var quickPanelController = QuickPanelController(state: quickPanelState)

  init(
    store: InMemoryHistoryStore = InMemoryHistoryStore(),
    payloadStore: InMemoryPayloadStore = InMemoryPayloadStore(),
    systemClient: SystemPasteboardClient = SystemPasteboardClient()
  ) {
    self.store = store
    self.payloadStore = payloadStore
    self.systemClient = systemClient
    self.ingestService = ClipboardIngestService(
      store: store,
      privacyPolicy: .standard,
      largeTextPolicy: .default
    )
    self.monitor = ClipboardMonitor(reader: systemClient)
    self.pasteController = PasteController(pasteboard: systemClient, eventPoster: systemClient)
  }
}
