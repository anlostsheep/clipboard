import AppKit
import ClipboardCore
import SwiftUI

@MainActor
final class ImportSettingsState: ObservableObject {
    @Published var candidates: [ImportSourceCandidate] = []
    @Published var selectedIDs: Set<String> = []
    @Published var statusText = "尚未扫描"
    @Published var hasScannedAutomaticSources = false

    private let discoverAutomaticSources: () -> [ImportSourceCandidate]

    init(discoverAutomaticSources: @escaping () -> [ImportSourceCandidate] = {
        ImportSourceDiscovery().discoverAutomaticSources()
    }) {
        self.discoverAutomaticSources = discoverAutomaticSources
    }

    func scanAutomaticSources() {
        let discovered = discoverAutomaticSources()
        candidates = discovered
        selectedIDs = Set(discovered.filter(\.isDefaultSelected).map(\.id))
        statusText = discovered.isEmpty ? "未发现可导入来源" : "发现 \(discovered.count) 个来源"
        hasScannedAutomaticSources = true
    }

    func upsertCandidate(_ candidate: ImportSourceCandidate) {
        candidates.removeAll { $0.id == candidate.id }
        candidates.append(candidate)
    }
}

struct ImportSettingsView: View {
    @ObservedObject var services: AppServices
    @StateObject private var importState = ImportSettingsState()

    @AppStorage(ClipboardAppSettings.maxHistoryCountStorageKey)
    private var maxHistoryCount: Int = ClipboardAppSettings.defaultStorageMaxHistoryCount

    @State private var latestReport: ImportReport?
    @State private var isRunning = false

    private let discovery = ImportSourceDiscovery()

    var body: some View {
        Form {
            Section("自动来源") {
                Button("扫描 Maccy 和 Clipaste") {
                    let settingsWindow = NSApp.keyWindow ?? NSApp.mainWindow
                    importState.scanAutomaticSources()
                    ClipboardSettingsWindow.restoreAfterExternalAuthorizationPrompt(settingsWindow)
                }
                .disabled(isRunning)

                Text("点击扫描后，macOS 可能要求允许访问 Maccy/Clipaste 数据目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if importState.candidates.isEmpty {
                    Text(importState.hasScannedAutomaticSources ? "未发现可导入来源" : "尚未扫描自动来源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(importState.candidates) { candidate in
                        Toggle(isOn: binding(for: candidate.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.displayName)

                                Text(candidate.databaseURL.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Text(candidateSummary(candidate))
                                    .font(.caption)
                                    .foregroundStyle(candidate.schemaKind == .unknown ? .orange : .secondary)
                            }
                        }
                        .disabled(isRunning || candidate.schemaKind == .unknown)
                    }
                }
            }

            Section("手动数据库") {
                Button("选择数据库文件") {
                    chooseManualDatabase()
                }
                .disabled(isRunning)
            }

            Section("导入") {
                Text(importState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let completionMessage {
                    Label(completionMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if let retentionWarning {
                    Label(retentionWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button(isRunning ? "导入中" : "开始导入") {
                        startImport()
                    }
                    .disabled(!canStartImport)

                    if let reportsDirectory = services.importReportsDirectory {
                        Button("打开报告文件夹") {
                            NSWorkspace.shared.open(reportsDirectory)
                        }
                    }
                }

                if services.importService == nil {
                    Text("当前存储不可写，无法导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let latestReport {
                Section("最新报告") {
                    Text(reportSummary(latestReport))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("复制报告 JSON") {
                        copyReport(latestReport)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var canStartImport: Bool {
        !isRunning
            && services.importService != nil
            && !Self.importableCandidates(from: importState.candidates, selectedIDs: importState.selectedIDs).isEmpty
    }

    private var retentionWarning: String? {
        Self.retentionLimitWarning(
            candidates: importState.candidates,
            selectedIDs: importState.selectedIDs,
            maxHistoryCount: maxHistoryCount
        )
    }

    private var completionMessage: String? {
        guard let latestReport, latestReport.status == .completed else {
            return nil
        }
        return Self.completedImportMessage(for: latestReport)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { importState.selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    importState.selectedIDs.insert(id)
                } else {
                    importState.selectedIDs.remove(id)
                }
            }
        )
    }

    private func chooseManualDatabase() {
        let settingsWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            ClipboardSettingsWindow.restoreAfterExternalAuthorizationPrompt(settingsWindow)
            return
        }

        do {
            let candidate = try discovery.classifyManualDatabase(url)
            importState.upsertCandidate(candidate)
            if candidate.schemaKind == .unknown {
                importState.selectedIDs.remove(candidate.id)
                importState.statusText = "无法识别数据库结构：\(url.lastPathComponent)"
            } else {
                importState.selectedIDs.insert(candidate.id)
                importState.statusText = "已添加 \(candidate.displayName)"
            }
        } catch {
            importState.statusText = "无法读取数据库：\(error.localizedDescription)"
        }
        ClipboardSettingsWindow.restoreAfterExternalAuthorizationPrompt(settingsWindow)
    }

    private func startImport() {
        guard let service = services.importService else {
            importState.statusText = "当前存储不可写，无法导入"
            return
        }

        let selected = Self.importableCandidates(from: importState.candidates, selectedIDs: importState.selectedIDs)
        guard !selected.isEmpty else {
            importState.statusText = importState.candidates.contains {
                importState.selectedIDs.contains($0.id) && $0.schemaKind == .unknown
            }
                ? "所选来源的数据库结构不受支持"
                : "请选择至少一个来源"
            return
        }

        isRunning = true
        importState.statusText = "正在导入"
        let reportsDirectory = services.importReportsDirectory

        Task.detached(priority: .userInitiated) {
            do {
                let imported = try Self.importRecords(from: selected)
                let report = try await service.importRecords(imported)
                await MainActor.run {
                    latestReport = report
                    importState.statusText = "导入完成"
                    isRunning = false
                }
            } catch {
                let failedReport = reportsDirectory.flatMap { Self.newestReport(in: $0) }
                await MainActor.run {
                    if let failedReport {
                        latestReport = failedReport
                    }
                    importState.statusText = "导入失败：\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
    }

    nonisolated static func importableCandidates(
        from candidates: [ImportSourceCandidate],
        selectedIDs: Set<String>
    ) -> [ImportSourceCandidate] {
        candidates.filter { selectedIDs.contains($0.id) && $0.schemaKind != .unknown }
    }

    nonisolated static func newestReport(in reportsDirectory: URL) -> ImportReport? {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> ImportReport? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(ImportReport.self, from: data)
            }
            .max { $0.createdAt < $1.createdAt }
    }

    nonisolated static func retentionLimitWarning(
        candidates: [ImportSourceCandidate],
        selectedIDs: Set<String>,
        maxHistoryCount: Int
    ) -> String? {
        let selectedRecordCount = candidates
            .filter { selectedIDs.contains($0.id) && $0.schemaKind != .unknown }
            .compactMap(\.recordCount)
            .reduce(0, +)

        guard selectedRecordCount > maxHistoryCount else {
            return nil
        }

        return "已选择约 \(selectedRecordCount) 条可导入记录，超过当前最多保留 \(maxHistoryCount) 条历史记录。导入会成功执行，但超出的旧记录会按保留策略被自动淘汰；如需保留更多，请先到“历史记录”设置中调高上限。"
    }

    nonisolated static func completedImportMessage(for report: ImportReport) -> String {
        "导入完成：扫描 \(report.scanned) 条，新增 \(report.imported) 条，合并 \(report.merged) 条，覆盖 \(report.replacedByNewest) 条，跳过 \(report.skipped) 条，失败 \(report.failed) 条。详细结果已写入报告。"
    }

    nonisolated private static func importRecords(from candidates: [ImportSourceCandidate]) throws -> [ImportedRecord] {
        let snapshotService = ImportSnapshotService()
        var imported: [ImportedRecord] = []

        for candidate in candidates {
            let snapshot = try snapshotService.snapshot(databaseURL: candidate.databaseURL)
            defer { try? FileManager.default.removeItem(at: snapshot.directoryURL) }

            switch candidate.schemaKind {
            case .maccy:
                imported.append(
                    contentsOf: try MaccyImporter(source: candidate.kind)
                        .importRecords(from: snapshot.databaseURL)
                )
            case .clipaste:
                imported.append(
                    contentsOf: try ClipasteImporter(source: candidate.kind)
                        .importRecords(from: snapshot.databaseURL)
                )
            case .unknown:
                continue
            }
        }

        return imported
    }

    private func candidateSummary(_ candidate: ImportSourceCandidate) -> String {
        let count = candidate.recordCount.map { "\($0) 条" } ?? "未知数量"
        return "\(candidate.schemaStatus) · \(count)"
    }

    private func reportSummary(_ report: ImportReport) -> String {
        "状态：\(report.status.rawValue)，扫描：\(report.scanned)，新增：\(report.imported)，合并：\(report.merged)，覆盖：\(report.replacedByNewest)，跳过：\(report.skipped)，失败：\(report.failed)"
    }

    private func copyReport(_ report: ImportReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let text = (try? String(data: encoder.encode(report), encoding: .utf8)) ?? "\(report)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        importState.statusText = "已复制报告 JSON"
    }
}
