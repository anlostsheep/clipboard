import Foundation

public struct ImportProgress: Equatable, Sendable {
  public let scanned: Int
  public let committedBatchCount: Int
  public let lastProcessedSourceRecordID: String?

  public init(
    scanned: Int,
    committedBatchCount: Int,
    lastProcessedSourceRecordID: String?
  ) {
    self.scanned = scanned
    self.committedBatchCount = committedBatchCount
    self.lastProcessedSourceRecordID = lastProcessedSourceRecordID
  }
}

private enum ImportBatchError: Error {
  case operationFailed(ImportFailure, Error)
}

public actor ImportService {
  private let historyStore: any ImportWritableHistoryStore
  private let payloadStore: any ClipboardPayloadStore
  private let reportsDirectory: URL
  private let builder: ImportRecordBuilder
  private let fileManager: FileManager

  public init(
    historyStore: any ImportWritableHistoryStore,
    payloadStore: any ClipboardPayloadStore,
    reportsDirectory: URL,
    builder: ImportRecordBuilder = ImportRecordBuilder(),
    fileManager: FileManager = .default
  ) {
    self.historyStore = historyStore
    self.payloadStore = payloadStore
    self.reportsDirectory = reportsDirectory
    self.builder = builder
    self.fileManager = fileManager
  }

  public func importRecords(
    _ imported: [ImportedRecord],
    batchSize: Int = 100,
    shouldCancel: @Sendable (ImportProgress) -> Bool = { _ in false }
  ) async throws -> ImportReport {
    let start = Date()
    var report = ImportReport(
      status: .completed,
      sources: Array(Set(imported.map { $0.source.rawValue })).sorted()
    )
    let effectiveBatchSize = max(1, batchSize)
    var batch: [ImportedRecord] = []

    do {
      for record in imported {
        report.scanned += 1
        report.lastProcessedSourceRecordID = record.sourceRecordID
        batch.append(record)

        if batch.count >= effectiveBatchSize {
          if shouldCancel(progress(from: report)) {
            report.status = .cancelled
            report.skipped += batch.count
            report.duration = Date().timeIntervalSince(start)
            try writeReport(report)
            return report
          }

          try await commit(batch, report: &report)
          batch.removeAll()
        }
      }

      if !batch.isEmpty {
        if shouldCancel(progress(from: report)) {
          report.status = .cancelled
          report.skipped += batch.count
        } else {
          try await commit(batch, report: &report)
        }
      }

      report.duration = Date().timeIntervalSince(start)
      try writeReport(report)
      return report
    } catch {
      report.status = .failed
      if case let ImportBatchError.operationFailed(failure, _) = error {
        report.failed += 1
        report.failures.append(failure)
      }
      report.duration = Date().timeIntervalSince(start)
      try? writeReport(report)
      throw error
    }
  }

  private func commit(_ records: [ImportedRecord], report: inout ImportReport) async throws {
    for imported in records {
      report.warnings.append(contentsOf: imported.warnings)
      do {
        let groupIDs = imported.groupNames.map(normalizedGroupID)
        let candidate = try builder.buildRecord(from: imported, groupIDs: groupIDs)

        if var existing = try await historyStore.record(forContentHash: candidate.contentHash) {
          let existingGroupIDs = existing.groupIds
          if candidate.lastCopiedAt >= existing.lastCopiedAt {
            let replacement = newestImportedRecord(
              imported: imported,
              candidate: candidate,
              existing: existing
            )
            let oldPayload: ClipboardPayload?
            do {
              oldPayload = try await payloadStore.loadPayload(for: replacement.id)
              try await payloadStore.save(imported.payload, for: replacement.id)
            } catch {
              throw ImportBatchError.operationFailed(failure(for: imported, error: error), error)
            }
            do {
              _ = try await historyStore.importRecord(replacement)
            } catch {
              try? await restorePayload(oldPayload, for: replacement.id)
              throw ImportBatchError.operationFailed(failure(for: imported, error: error), error)
            }
            report.replacedByNewest += 1
            appendIntroducedGroupIDs(candidate.groupIds, existingGroupIDs: existingGroupIDs, report: &report)
          } else {
            existing = existingRecordAfterMetadataMerge(existing: existing, candidate: candidate)
            do {
              _ = try await historyStore.importRecord(existing)
            } catch {
              throw ImportBatchError.operationFailed(failure(for: imported, error: error), error)
            }
            report.merged += 1
            appendIntroducedGroupIDs(candidate.groupIds, existingGroupIDs: existingGroupIDs, report: &report)
          }
        } else {
          do {
            try await payloadStore.save(imported.payload, for: candidate.id)
          } catch {
            throw ImportBatchError.operationFailed(failure(for: imported, error: error), error)
          }
          do {
            _ = try await historyStore.importRecord(candidate)
          } catch {
            try? await payloadStore.delete(for: candidate.id)
            throw ImportBatchError.operationFailed(failure(for: imported, error: error), error)
          }
          report.imported += 1
          appendIntroducedGroupIDs(candidate.groupIds, existingGroupIDs: [], report: &report)
        }
      } catch {
        if case ImportBatchError.operationFailed = error {
          throw error
        }
        report.failed += 1
        report.failures.append(failure(for: imported, error: error))
      }
    }

    report.committedBatchCount += 1
  }

  private func newestImportedRecord(
    imported: ImportedRecord,
    candidate: ClipboardRecord,
    existing: ClipboardRecord
  ) -> ClipboardRecord {
    ClipboardRecord(
      id: existing.id,
      contentHash: candidate.contentHash,
      primaryType: candidate.primaryType,
      title: candidate.title,
      plainTextPreview: candidate.plainTextPreview,
      sourceAppBundleId: candidate.sourceAppBundleId,
      sourceAppName: candidate.sourceAppName,
      sourceDeviceHint: candidate.sourceDeviceHint,
      createdAt: existing.createdAt,
      lastCopiedAt: candidate.lastCopiedAt,
      copyCount: boundedCopyCount(existing.copyCount + candidate.copyCount),
      isPinned: existing.isPinned || candidate.isPinned,
      isFavorite: existing.isFavorite || candidate.isFavorite,
      groupIds: orderedUnion(existing.groupIds, candidate.groupIds),
      retentionExempt: existing.retentionExempt || candidate.retentionExempt ||
        existing.isPinned || existing.isFavorite || imported.isPinned || imported.isFavorite,
      metadata: candidate.metadata ?? existing.metadata,
      pasteboardTypes: existing.pasteboardTypes.union(candidate.pasteboardTypes)
    )
  }

  private func existingRecordAfterMetadataMerge(
    existing: ClipboardRecord,
    candidate: ClipboardRecord
  ) -> ClipboardRecord {
    var merged = existing
    merged.copyCount = boundedCopyCount(existing.copyCount + candidate.copyCount)
    merged.groupIds = orderedUnion(existing.groupIds, candidate.groupIds)
    merged.isPinned = existing.isPinned || candidate.isPinned
    merged.isFavorite = existing.isFavorite || candidate.isFavorite
    merged.retentionExempt = existing.retentionExempt || candidate.retentionExempt ||
      merged.isPinned || merged.isFavorite
    merged.pasteboardTypes = existing.pasteboardTypes.union(candidate.pasteboardTypes)
    return merged
  }

  private func progress(from report: ImportReport) -> ImportProgress {
    ImportProgress(
      scanned: report.scanned,
      committedBatchCount: report.committedBatchCount,
      lastProcessedSourceRecordID: report.lastProcessedSourceRecordID
    )
  }

  private func restorePayload(_ payload: ClipboardPayload?, for recordID: UUID) async throws {
    if let payload {
      try await payloadStore.save(payload, for: recordID)
    } else {
      try await payloadStore.delete(for: recordID)
    }
  }

  private func failure(for imported: ImportedRecord, error: Error) -> ImportFailure {
    ImportFailure(
      source: imported.source,
      sourceRecordID: imported.sourceRecordID,
      titleOrPreview: imported.title.isEmpty ? imported.plainTextPreview : imported.title,
      reason: String(describing: error)
    )
  }

  private func appendIntroducedGroupIDs(
    _ candidateGroupIDs: [String],
    existingGroupIDs: [String],
    report: inout ImportReport
  ) {
    for groupID in candidateGroupIDs
      where !existingGroupIDs.contains(groupID) && !report.createdGroupIDs.contains(groupID) {
      report.createdGroupIDs.append(groupID)
    }
  }

  private func normalizedGroupID(_ name: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let replacedScalars = trimmed.unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
    }
    let slug = String(replacedScalars)
      .split(separator: "-")
      .joined(separator: "-")
    return slug.isEmpty ? "imported" : slug
  }

  private func orderedUnion(_ first: [String], _ second: [String]) -> [String] {
    var result = first
    for value in second where !result.contains(value) {
      result.append(value)
    }
    return result
  }

  private func boundedCopyCount(_ value: Int) -> Int {
    min(max(1, value), 1_000_000)
  }

  private func writeReport(_ report: ImportReport) throws {
    if !fileManager.fileExists(atPath: reportsDirectory.path) {
      try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
    }

    let stamp = ISO8601DateFormatter()
      .string(from: report.createdAt)
      .replacingOccurrences(of: ":", with: "")
    let sourceSuffix = report.sources.first ?? "import"
    let filename = "\(stamp)-\(normalizedFilenameComponent(sourceSuffix))-import.json"
    let url = reportsDirectory.appendingPathComponent(filename, isDirectory: false)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: url, options: .atomic)
  }

  private func normalizedFilenameComponent(_ value: String) -> String {
    let replacedScalars = value.lowercased().unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
    }
    let slug = String(replacedScalars)
      .split(separator: "-")
      .joined(separator: "-")
    return slug.isEmpty ? "import" : slug
  }
}
