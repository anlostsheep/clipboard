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
  let captureCoordinator: ClipboardCaptureCoordinator
  let pasteController: PasteController
  lazy var quickPanelState = QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 50),
    payloadStore: payloadStore,
    pasteController: pasteController
  )
  lazy var quickPanelController = QuickPanelController(
    state: quickPanelState,
    prepareForShow: { [weak self] in
      await self?.prepareQuickPanelForShow()
    }
  )

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
    self.captureCoordinator = ClipboardCaptureCoordinator(
      monitor: monitor,
      ingestService: ingestService,
      payloadStore: payloadStore
    )
    self.pasteController = PasteController(pasteboard: systemClient, eventPoster: systemClient)
  }

  private func prepareQuickPanelForShow() async {
    do {
      _ = try await captureCoordinator.captureLatestChange()
    } catch {
      NSLog("Failed to capture latest clipboard item before showing QuickPanel: \(error.localizedDescription)")
    }
  }
}
