import Foundation

public struct ImportSnapshot: Sendable {
  public let databaseURL: URL
  public let directoryURL: URL

  public init(databaseURL: URL, directoryURL: URL) {
    self.databaseURL = databaseURL
    self.directoryURL = directoryURL
  }
}

public struct ImportSnapshotService: Sendable {
  public init() {}

  public func snapshot(databaseURL: URL) throws -> ImportSnapshot {
    let fileManager = FileManager.default
    let directoryURL = fileManager.temporaryDirectory
      .appendingPathComponent("clipboard-import-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    let snapshotDatabaseURL = directoryURL.appendingPathComponent(databaseURL.lastPathComponent)
    try fileManager.copyItem(at: databaseURL, to: snapshotDatabaseURL)

    for suffix in ["-wal", "-shm"] {
      let sourceSidecarURL = URL(fileURLWithPath: databaseURL.path + suffix)
      guard fileManager.fileExists(atPath: sourceSidecarURL.path) else { continue }

      let destinationSidecarURL = directoryURL.appendingPathComponent(databaseURL.lastPathComponent + suffix)
      try fileManager.copyItem(at: sourceSidecarURL, to: destinationSidecarURL)
    }

    return ImportSnapshot(databaseURL: snapshotDatabaseURL, directoryURL: directoryURL)
  }
}
