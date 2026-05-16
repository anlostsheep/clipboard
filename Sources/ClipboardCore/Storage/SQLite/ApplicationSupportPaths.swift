import Foundation

/// Resolves persistent data storage location. Allows injecting a custom base directory for tests.
public struct ApplicationSupportPaths: Sendable {
  public let baseDirectory: URL
  public let databaseFile: URL
  public let payloadsDirectory: URL

  public init(bundleIdentifier: String, customBase: URL? = nil) throws {
    let base: URL
    if let customBase {
      base = customBase
    } else {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      base = support.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }
    self.baseDirectory = base
    self.databaseFile = base.appendingPathComponent("clipboard.sqlite", isDirectory: false)
    self.payloadsDirectory = base.appendingPathComponent("payloads", isDirectory: true)
  }

  /// Ensures baseDirectory and payloadsDirectory exist; throws if not writable.
  public func prepare() throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: baseDirectory.path) {
      try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: payloadsDirectory.path) {
      try fm.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)
    }
    // Probe writability
    let probe = baseDirectory.appendingPathComponent(".write-probe", isDirectory: false)
    try Data().write(to: probe, options: .atomic)
    try fm.removeItem(at: probe)
  }
}
