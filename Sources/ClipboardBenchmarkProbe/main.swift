import ClipboardCore
import ClipboardPlatform
import Foundation

@main
struct ClipboardBenchmarkProbe {
  fileprivate static let defaultBundleID = "com.local.clipboard-manager"

  static func main() async throws {
    let arguments = try ProbeArguments.parse(CommandLine.arguments.dropFirst())
    let paths = try ApplicationSupportPaths(bundleIdentifier: arguments.bundleID)
    let report = try await run(paths: paths, bundleID: arguments.bundleID)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    try FileManager.default.createDirectory(
      at: arguments.outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: arguments.outputURL, options: .atomic)

    printSummary(report, outputURL: arguments.outputURL)
  }

  private static func run(paths: ApplicationSupportPaths, bundleID: String) async throws -> BenchmarkReport {
    let snapshot = try BenchmarkDatabaseSnapshot(sourceDatabaseFile: paths.databaseFile)
    let (store, loadMetric) = try measureStoreLoad(databaseFile: snapshot.databaseFile)
    let records = try await store.fetchAll()

    let fetchRecent = try await measure(name: "fetch_recent_50_ms", iterations: 10) {
      _ = try await store.fetchPage(HistoryQuery(), limit: 50)
    }
    let fetchHTTP = try await measure(name: "search_http_50_ms", iterations: 10) {
      _ = try await store.fetchPage(HistoryQuery(text: "http"), limit: 50)
    }

    return BenchmarkReport(
      generatedAt: Date(),
      bundleID: bundleID,
      paths: BenchmarkPaths(
        databaseFile: paths.databaseFile.path,
        payloadsDirectory: paths.payloadsDirectory.path
      ),
      dataset: DatasetSummary(
        recordCount: records.count,
        payloadBytes: payloadBytes(in: paths.payloadsDirectory),
        typeCounts: typeCounts(records),
        pinnedCount: records.filter(\.isPinned).count
      ),
      metrics: [loadMetric, fetchRecent, fetchHTTP],
      maccyComparison: .notComparable
    )
  }

  private static func measureStoreLoad(databaseFile: URL) throws -> (SQLiteHistoryStore, BenchmarkMetric) {
    let start = ContinuousClock.now
    let store = try SQLiteHistoryStore(databaseFile: databaseFile)
    let elapsed = milliseconds(from: start, to: ContinuousClock.now)
    return (
      store,
      BenchmarkMetric(name: "store_load_ms", samplesMs: [elapsed])
    )
  }

  private static func measure(
    name: String,
    iterations: Int,
    operation: () async throws -> Void
  ) async throws -> BenchmarkMetric {
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
      let start = ContinuousClock.now
      try await operation()
      samples.append(milliseconds(from: start, to: ContinuousClock.now))
    }
    return BenchmarkMetric(name: name, samplesMs: samples)
  }

  private static func milliseconds(
    from start: ContinuousClock.Instant,
    to end: ContinuousClock.Instant
  ) -> Double {
    Double(start.duration(to: end).components.attoseconds) / 1_000_000_000_000_000.0 +
      Double(start.duration(to: end).components.seconds) * 1_000
  }

  private static func payloadBytes(in directory: URL) -> Int64 {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }

    var total: Int64 = 0
    for case let url as URL in enumerator {
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true else {
        continue
      }
      total += Int64(values.fileSize ?? 0)
    }
    return total
  }

  private static func typeCounts(_ records: [ClipboardRecord]) -> [String: Int] {
    Dictionary(grouping: records, by: { $0.primaryType.rawValue })
      .mapValues(\.count)
  }

  private static func printSummary(_ report: BenchmarkReport, outputURL: URL) {
    print("Clipboard benchmark report: \(outputURL.path)")
    print("Bundle ID: \(report.bundleID)")
    print("Records: \(report.dataset.recordCount)")
    print("Payload bytes: \(report.dataset.payloadBytes)")
    print("Pinned records: \(report.dataset.pinnedCount)")
    print("Type counts: \(report.dataset.typeCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
    print("Metrics:")
    for metric in report.metrics {
      print(String(format: "  %@ median=%.3fms p95=%.3fms", metric.name, metric.medianMs, metric.p95Ms))
    }
    print("Maccy comparison: \(report.maccyComparison.rawValue)")
  }
}

private final class BenchmarkDatabaseSnapshot {
  let databaseFile: URL
  private let directory: URL

  init(sourceDatabaseFile: URL) throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent(
      "clipboard-benchmark-\(UUID().uuidString)",
      isDirectory: true
    )
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    self.directory = directory
    self.databaseFile = directory.appendingPathComponent(sourceDatabaseFile.lastPathComponent)

    if fm.fileExists(atPath: sourceDatabaseFile.path) {
      try fm.copyItem(at: sourceDatabaseFile, to: databaseFile)
    }

    for suffix in ["-wal", "-shm"] {
      let sourceSidecar = URL(fileURLWithPath: sourceDatabaseFile.path + suffix)
      guard fm.fileExists(atPath: sourceSidecar.path) else { continue }
      let targetSidecar = URL(fileURLWithPath: databaseFile.path + suffix)
      try fm.copyItem(at: sourceSidecar, to: targetSidecar)
    }
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }
}

private struct ProbeArguments {
  let bundleID: String
  let outputURL: URL

  static func parse<S: Sequence>(_ rawArguments: S) throws -> ProbeArguments where S.Element == String {
    var bundleID = ClipboardBenchmarkProbe.defaultBundleID
    var outputPath: String?
    var iterator = rawArguments.makeIterator()

    while let argument = iterator.next() {
      switch argument {
      case "--bundle-id":
        guard let value = iterator.next(), !value.isEmpty else {
          throw ProbeArgumentError.missingValue("--bundle-id")
        }
        bundleID = value
      case "--output":
        guard let value = iterator.next(), !value.isEmpty else {
          throw ProbeArgumentError.missingValue("--output")
        }
        outputPath = value
      case "--help", "-h":
        throw ProbeArgumentError.help
      default:
        throw ProbeArgumentError.unknown(argument)
      }
    }

    guard let outputPath else {
      throw ProbeArgumentError.missingValue("--output")
    }

    return ProbeArguments(
      bundleID: bundleID,
      outputURL: URL(fileURLWithPath: outputPath)
    )
  }
}

private enum ProbeArgumentError: Error, CustomStringConvertible {
  case help
  case missingValue(String)
  case unknown(String)

  var description: String {
    switch self {
    case .help:
      return Self.usage
    case .missingValue(let argument):
      return "Missing value for \(argument)\n\(Self.usage)"
    case .unknown(let argument):
      return "Unknown argument: \(argument)\n\(Self.usage)"
    }
  }

  private static let usage = "usage: ClipboardBenchmarkProbe [--bundle-id BUNDLE_ID] --output REPORT_JSON"
}

private struct BenchmarkReport: Encodable {
  let generatedAt: Date
  let bundleID: String
  let paths: BenchmarkPaths
  let dataset: DatasetSummary
  let metrics: [BenchmarkMetric]
  let maccyComparison: BenchmarkComparisonResult
}

private struct BenchmarkPaths: Encodable {
  let databaseFile: String
  let payloadsDirectory: String
}

private struct DatasetSummary: Encodable {
  let recordCount: Int
  let payloadBytes: Int64
  let typeCounts: [String: Int]
  let pinnedCount: Int
}

private struct BenchmarkMetric: Encodable {
  let name: String
  let samplesMs: [Double]

  var medianMs: Double {
    guard !samplesMs.isEmpty else { return 0 }
    let sorted = samplesMs.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
  }

  var p95Ms: Double {
    percentile(0.95)
  }

  private func percentile(_ quantile: Double) -> Double {
    guard !samplesMs.isEmpty else { return 0 }
    let sorted = samplesMs.sorted()
    let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * quantile).rounded(.up))))
    return sorted[index]
  }

  enum CodingKeys: String, CodingKey {
    case name
    case samplesMs
    case medianMs
    case p95Ms
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(samplesMs, forKey: .samplesMs)
    try container.encode(medianMs, forKey: .medianMs)
    try container.encode(p95Ms, forKey: .p95Ms)
  }
}
