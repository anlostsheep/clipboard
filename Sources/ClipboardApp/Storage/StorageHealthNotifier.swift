import Foundation
import UserNotifications
import os.log

@MainActor
final class StorageHealthNotifier {
  // Categorizes the type of storage failure for deduplication
  enum Failure: String {
    case diskFull
    case permission
    case corruption
    case other
  }

  private var lastNotifiedFailure: Failure?
  private static let logger = Logger(subsystem: "clipboard.storage", category: "Notifier")

  /// Sends a failure notification only if the failure category has changed since the last notification.
  func notifyFailure(_ failure: Failure, message: String) async {
    guard lastNotifiedFailure != failure else { return }
    lastNotifiedFailure = failure
    await sendNotification(title: "持久化写入失败", body: message)
  }

  /// Sends an auto-eviction notification if the user has opted in via settings.
  func notifyAutoEvict(removed: Int, freed: String) async {
    guard ClipboardAppSettings.storageNotifyOnAutoEvict() else { return }
    await sendNotification(
      title: "已自动清理空间",
      body: "剪贴板自动清理了 \(removed) 条最旧记录，释放约 \(freed)。"
    )
  }

  /// Sends a recovery notification only if a failure had previously been notified.
  func notifyRecovered() async {
    guard lastNotifiedFailure != nil else { return }
    lastNotifiedFailure = nil
    await sendNotification(title: "持久化已恢复", body: "剪贴板写入已恢复正常。")
  }

  private func sendNotification(title: String, body: String) async {
    let center = UNUserNotificationCenter.current()
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      try await center.add(request)
    } catch {
      Self.logger.error("notification failed: \(String(describing: error))")
    }
  }
}
