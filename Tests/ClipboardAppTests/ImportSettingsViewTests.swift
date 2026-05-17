import XCTest
import ClipboardCore
@testable import ClipboardApp

final class ImportSettingsViewTests: XCTestCase {
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

    private func candidate(id: String, schemaKind: ImportSchemaKind) -> ImportSourceCandidate {
        ImportSourceCandidate(
            id: id,
            kind: .manualMaccy,
            displayName: id,
            databaseURL: URL(fileURLWithPath: "/tmp/\(id).sqlite"),
            appBundleID: nil,
            appVersion: nil,
            storeSizeBytes: 0,
            recordCount: nil,
            typeDistribution: [:],
            lastModifiedAt: nil,
            schemaKind: schemaKind,
            schemaStatus: schemaKind == .unknown ? "Unsupported schema" : "OK",
            isDefaultSelected: schemaKind != .unknown
        )
    }

    private func writeReport(_ report: ImportReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: url, options: .atomic)
    }
}
