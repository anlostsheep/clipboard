import XCTest
import ClipboardCore
@testable import ClipboardApp

final class ImportSettingsViewTests: XCTestCase {
    @MainActor
    func testImportStateDoesNotScanAutomaticSourcesOnInitialization() {
        var scanCount = 0
        _ = ImportSettingsState(discoverAutomaticSources: {
            scanCount += 1
            return []
        })

        XCTAssertEqual(scanCount, 0)
    }

    @MainActor
    func testImportStateScansAutomaticSourcesOnlyWhenRequested() {
        let expected = candidate(id: "maccy", schemaKind: .maccy)
        let state = ImportSettingsState(discoverAutomaticSources: {
            [expected]
        })

        state.scanAutomaticSources()

        XCTAssertEqual(state.candidates, [expected])
        XCTAssertEqual(state.selectedIDs, [expected.id])
        XCTAssertEqual(state.statusText, "发现 1 个来源")
    }

    func testRetentionWarningAppearsWhenSelectedRecordCountExceedsLimit() {
        let first = Self.candidate(id: "maccy", schemaKind: .maccy, recordCount: 150)
        let second = Self.candidate(id: "clipaste", schemaKind: .clipaste, recordCount: 100)

        let warning = ImportSettingsView.retentionLimitWarning(
            candidates: [first, second],
            selectedIDs: [first.id, second.id],
            maxHistoryCount: 200
        )

        XCTAssertEqual(
            warning,
            "已选择约 250 条可导入记录，超过当前最多保留 200 条历史记录。导入会成功执行，但超出的旧记录会按保留策略被自动淘汰；如需保留更多，请先到“历史记录”设置中调高上限。"
        )
    }

    func testRetentionWarningIgnoresUnselectedAndUnknownRecordCounts() {
        let selected = Self.candidate(id: "maccy", schemaKind: .maccy, recordCount: 150)
        let unselected = Self.candidate(id: "clipaste", schemaKind: .clipaste, recordCount: 500)
        let unknownCount = Self.candidate(id: "manual", schemaKind: .maccy, recordCount: nil)

        let warning = ImportSettingsView.retentionLimitWarning(
            candidates: [selected, unselected, unknownCount],
            selectedIDs: [selected.id, unknownCount.id],
            maxHistoryCount: 200
        )

        XCTAssertNil(warning)
    }

    func testCompletedImportMessageSummarizesSuccessfulReport() {
        let report = ImportReport(
            status: .completed,
            sources: ["maccy", "clipaste"],
            scanned: 2834,
            imported: 500,
            merged: 100,
            replacedByNewest: 188,
            skipped: 2046,
            failed: 0
        )

        let message = ImportSettingsView.completedImportMessage(for: report)

        XCTAssertEqual(
            message,
            "导入完成：扫描 2834 条，新增 500 条，合并 100 条，覆盖 188 条，跳过 2046 条，失败 0 条。详细结果已写入报告。"
        )
    }

    func testSettingsPageIncludesImportPage() {
        XCTAssertTrue(SettingsPage.allCases.contains(.importData))
    }

    func testImportPageUsesImportIcon() {
        XCTAssertEqual(SettingsPage.importData.systemImage, "square.and.arrow.down")
    }

    func testImportableCandidatesExcludeUnsupportedSchemas() {
        let supported = candidate(id: "supported", schemaKind: .maccy)
        let unsupported = candidate(id: "unsupported", schemaKind: .unknown)

        let result = ImportSettingsView.importableCandidates(
            from: [supported, unsupported],
            selectedIDs: [supported.id, unsupported.id]
        )

        XCTAssertEqual(result, [supported])
    }

    func testNewestReportLoadsLatestFailedJSONReport() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-import-report-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try writeReport(
            ImportReport(createdAt: Date(timeIntervalSince1970: 100), status: .completed, sources: ["maccy"]),
            to: tempDir.appendingPathComponent("older-import.json")
        )
        try writeReport(
            ImportReport(createdAt: Date(timeIntervalSince1970: 200), status: .failed, sources: ["maccy"], failed: 1),
            to: tempDir.appendingPathComponent("newer-import.json")
        )

        let report = try XCTUnwrap(ImportSettingsView.newestReport(in: tempDir))

        XCTAssertEqual(report.status, .failed)
        XCTAssertEqual(report.failed, 1)
    }

    private static func candidate(
        id: String,
        schemaKind: ImportSchemaKind,
        recordCount: Int? = nil
    ) -> ImportSourceCandidate {
        ImportSourceCandidate(
            id: id,
            kind: .manualMaccy,
            displayName: id,
            databaseURL: URL(fileURLWithPath: "/tmp/\(id).sqlite"),
            appBundleID: nil,
            appVersion: nil,
            storeSizeBytes: 0,
            recordCount: recordCount,
            typeDistribution: [:],
            lastModifiedAt: nil,
            schemaKind: schemaKind,
            schemaStatus: schemaKind == .unknown ? "Unsupported schema" : "OK",
            isDefaultSelected: schemaKind != .unknown
        )
    }

    private func candidate(id: String, schemaKind: ImportSchemaKind) -> ImportSourceCandidate {
        Self.candidate(id: id, schemaKind: schemaKind)
    }

    private func writeReport(_ report: ImportReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }
}
