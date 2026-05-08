import AppKit
import ClipboardCore
import ClipboardPlatform
import Combine
import Foundation
import os.log

// MARK: - HealthBox

/// Indirect reference that lets DefaultStorageFailureHandler update AppServices.storageHealth
/// without capturing `self` before all stored properties are initialized.
@MainActor
final class HealthBox {
  weak var owner: AppServices?
  init() {}
}

// MARK: - DefaultStorageFailureHandler

final class DefaultStorageFailureHandler: StorageFailureHandler {
  private let monitor: ClipboardMonitor
  private let store: any HistoryStore
  private let notifier: StorageHealthNotifier
  private let onHealthChange: @Sendable (AppServices.StorageHealth) async -> Void

  init(
    monitor: ClipboardMonitor,
    store: any HistoryStore,
    notifier: StorageHealthNotifier,
    onHealthChange: @escaping @Sendable (AppServices.StorageHealth) async -> Void
  ) {
    self.monitor = monitor
    self.store = store
    self.notifier = notifier
    self.onHealthChange = onHealthChange
  }

  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool {
    let strategy = await MainActor.run { ClipboardAppSettings.storageFailureStrategy() }
    let message = "磁盘空间不足：\(String(describing: error))"

    switch strategy {
    case .continueEvicting:
      do {
        let removed = try await store.evictOldest(percent: 0.10)
        if removed == 0 {
          await monitor.pause()
          await notifier.notifyFailure(.diskFull, message: message + "（无可删记录，已暂停监控）")
          await onHealthChange(.disabled(reason: "磁盘满且无可删记录"))
          return true
        }
        // Eviction succeeded — notify the user (Layer 2 eviction path).
        await notifier.notifyAutoEvict(removed: removed)
        return false  // let the caller retry
      } catch {
        await notifier.notifyFailure(.other, message: String(describing: error))
        return true
      }
    case .pauseMonitoring:
      await monitor.pause()
      await notifier.notifyFailure(.diskFull, message: message)
      await onHealthChange(.disabled(reason: "用户策略：暂停监控"))
      return true
    case .skipRecord:
      await notifier.notifyFailure(.diskFull, message: message)
      await onHealthChange(.failing(reason: "跳过当前记录"))
      return true
    }
  }

  func reportSuccess() async {
    await notifier.notifyRecovered()
    await onHealthChange(.ok)
  }
}

// MARK: - AppServices

@MainActor
final class AppServices: ObservableObject {
  enum StorageHealth {
    case ok
    case disabled(reason: String)
    case failing(reason: String)
  }

  let store: any HistoryStore
  let payloadStore: any ClipboardPayloadStore
  let systemClient: SystemPasteboardClient
  let ingestService: ClipboardIngestService
  let monitor: ClipboardMonitor
  let captureCoordinator: ClipboardCaptureCoordinator
  let pasteController: PasteController
  @Published private(set) var storageHealth: StorageHealth = .ok

  let storageNotifier = StorageHealthNotifier()

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

  private static let logger = Logger(subsystem: "clipboard.app", category: "AppServices")

  init() {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.local.clipboard-manager"
    let (storeImpl, payloadImpl, health) = AppServices.makeStorage(bundleId: bundleId)
    self.store = storeImpl
    self.payloadStore = payloadImpl
    self.storageHealth = health
    self.systemClient = SystemPasteboardClient()
    self.ingestService = ClipboardIngestService(
      store: storeImpl,
      privacyPolicy: .standard,
      largeTextPolicy: .default
    )
    self.monitor = ClipboardMonitor(reader: systemClient)
    // Use a box so the closure can weakly reference AppServices without
    // capturing `self` before all stored properties are initialized.
    let healthBox = HealthBox()
    let handler = DefaultStorageFailureHandler(
      monitor: monitor,
      store: storeImpl,
      notifier: storageNotifier,
      onHealthChange: { newHealth in
        await MainActor.run { healthBox.owner?.storageHealth = newHealth }
      }
    )
    self.captureCoordinator = ClipboardCaptureCoordinator(
      monitor: monitor,
      ingestService: ingestService,
      payloadStore: payloadImpl,
      failureHandler: handler
    )
    self.pasteController = PasteController(pasteboard: systemClient, eventPoster: systemClient)
    healthBox.owner = self

    // Notify user if storage could not be initialized
    if case .disabled(let reason) = storageHealth {
      Task { @MainActor in
        await self.storageNotifier.notifyFailure(.permission, message: reason)
      }
    }
  }

  /// Attempts to construct SQLite-backed storage; returns InMemory + .disabled on failure.
  private static func makeStorage(bundleId: String) -> (any HistoryStore, any ClipboardPayloadStore, StorageHealth) {
    do {
      let paths = try ApplicationSupportPaths(bundleIdentifier: bundleId)
      try paths.prepare()
      let policy = RetentionPolicy(
        maxCount: ClipboardAppSettings.storageMaxHistoryCount(),
        maxAgeDays: ClipboardAppSettings.storageMaxAgeDays()
      )
      let sqliteStore = try SQLiteHistoryStore(
        databaseFile: paths.databaseFile,
        retentionPolicy: policy
      )
      let healing = SelfHealingHistoryStore(underlying: sqliteStore)
      let payloads = try SQLitePayloadStore(payloadsDirectory: paths.payloadsDirectory)
      logger.info("storage initialized at \(paths.baseDirectory.path)")

      // Schedule orphan payload file scan 5s after launch (spec §6).
      // Captures sqliteStore and payloads directly (pre-wrapping) to access
      // concrete methods not on the HistoryStore protocol.
      // Use a local logger to avoid capturing the @MainActor-isolated static property.
      let scanLogger = Logger(subsystem: "clipboard.app", category: "AppServices")
      Task.detached(priority: .background) {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        let prefixes = await sqliteStore.referencedPayloadFilenamePrefixes()
        do {
          let removed = try await payloads.removeOrphans(keepingPrefixes: prefixes)
          if removed > 0 {
            scanLogger.info("orphan scan removed \(removed) stale payload file(s)")
          }
        } catch {
          scanLogger.error("orphan scan failed: \(String(describing: error))")
        }
      }

      return (healing, payloads, .ok)
    } catch {
      logger.error("storage init failed: \(String(describing: error))")
      let reason = "无法访问存储位置：\(error.localizedDescription)"
      _ = AppServices.presentStartupFailure(reason: reason)
      return (InMemoryHistoryStore(), InMemoryPayloadStore(), .disabled(reason: reason))
    }
  }

  private static func presentStartupFailure(reason: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "无法持久化剪贴板历史"
    alert.informativeText = """
      剪贴板管理器无法访问存储位置。

      \(reason)

      可能原因：磁盘空间不足、文件夹权限异常、或应用从只读位置（如 DMG）运行。
      """
    alert.addButton(withTitle: "在 Finder 中显示")
    alert.addButton(withTitle: "重试")
    alert.addButton(withTitle: "仅本次会话运行")
    alert.addButton(withTitle: "退出")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      let support = (try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )) ?? URL(fileURLWithPath: NSHomeDirectory())
      NSWorkspace.shared.activateFileViewerSelecting([support])
      return false
    case .alertSecondButtonReturn:
      return true  // caller should retry makeStorage
    case .alertThirdButtonReturn:
      return false
    default:
      NSApp.terminate(nil)
      return false
    }
  }

  private func prepareQuickPanelForShow() async {
    do {
      _ = try await captureCoordinator.captureLatestChange()
    } catch {
      NSLog("Failed to capture latest clipboard item before showing QuickPanel: \(error.localizedDescription)")
    }
  }
}
