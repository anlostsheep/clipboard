import Foundation

public actor ClipboardCaptureLoop {
  public typealias CaptureAction = @Sendable () async throws -> Void
  public typealias SleepAction = @Sendable (UInt64) async -> Void

  private let intervalNanoseconds: UInt64
  private let capture: CaptureAction
  private let sleep: SleepAction
  private var task: Task<Void, Never>?

  public init(
    coordinator: ClipboardCaptureCoordinator,
    intervalNanoseconds: UInt64 = 500_000_000
  ) {
    self.init(
      intervalNanoseconds: intervalNanoseconds,
      capture: {
        _ = try await coordinator.captureLatestChange()
      },
      sleep: { nanoseconds in
        try? await Task.sleep(nanoseconds: nanoseconds)
      }
    )
  }

  public init(
    intervalNanoseconds: UInt64,
    capture: @escaping CaptureAction,
    sleep: @escaping SleepAction
  ) {
    self.intervalNanoseconds = intervalNanoseconds
    self.capture = capture
    self.sleep = sleep
  }

  public var isRunning: Bool {
    task != nil
  }

  public func start() {
    guard task == nil else { return }

    let intervalNanoseconds = intervalNanoseconds
    let capture = capture
    let sleep = sleep
    task = Task {
      while !Task.isCancelled {
        do {
          try await capture()
        } catch {
          // A single unreadable pasteboard item should not stop future captures.
        }

        guard !Task.isCancelled else { break }
        await sleep(intervalNanoseconds)
      }
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
  }
}
