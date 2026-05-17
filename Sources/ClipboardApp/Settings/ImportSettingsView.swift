import AppKit
import ClipboardCore
import SwiftUI

struct ImportSettingsView: View {
    @ObservedObject var services: AppServices

    @State private var candidates: [ImportSourceCandidate] = []
    @State private var selectedIDs: Set<String> = []
    @State private var latestReport: ImportReport?
    @State private var statusText = "尚未扫描"
    @State private var isRunning = false

    private let discovery = ImportSourceDiscovery()

    var body: some View {
        Form {
            Section("自动来源") {
                Button("扫描 Maccy 和 Clipaste") {
                    scanAutomaticSources()
                }
                .disabled(isRunning)

                if candidates.isEmpty {
                    Text("未发现可导入来源")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(candidates) { candidate in
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
                        .disabled(isRunning)
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
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        .onAppear {
            scanAutomaticSources()
        }
    }

    private var canStartImport: Bool {
        !isRunning && services.importService != nil && candidates.contains { selectedIDs.contains($0.id) }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isSelected in
                if isSelected {
                    selectedIDs.insert(id)
                } else {
                    selectedIDs.remove(id)
                }
            }
        )
    }

    private func scanAutomaticSources() {
        let discovered = discovery.discoverAutomaticSources()
        candidates = discovered
        selectedIDs = Set(discovered.filter(\.isDefaultSelected).map(\.id))
        latestReport = nil
        statusText = discovered.isEmpty ? "未发现可导入来源" : "发现 \(discovered.count) 个来源"
    }

    private func chooseManualDatabase() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let candidate = try discovery.classifyManualDatabase(url)
            upsertCandidate(candidate)
            if candidate.schemaKind == .unknown {
                statusText = "无法识别数据库结构：\(url.lastPathComponent)"
            } else {
                selectedIDs.insert(candidate.id)
                statusText = "已添加 \(candidate.displayName)"
            }
        } catch {
            statusText = "无法读取数据库：\(error.localizedDescription)"
        }
    }

    private func startImport() {
        guard let service = services.importService else {
            statusText = "当前存储不可写，无法导入"
            return
        }

        let selected = candidates.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else {
            statusText = "请选择至少一个来源"
            return
        }

        isRunning = true
        latestReport = nil
        statusText = "正在导入"

        Task.detached(priority: .userInitiated) {
            do {
                let imported = try Self.importRecords(from: selected)
                let report = try await service.importRecords(imported)
                await MainActor.run {
                    latestReport = report
                    statusText = "导入完成"
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    statusText = "导入失败：\(error.localizedDescription)"
                    isRunning = false
                }
            }
        }
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

    private func upsertCandidate(_ candidate: ImportSourceCandidate) {
        candidates.removeAll { $0.id == candidate.id }
        candidates.append(candidate)
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
        statusText = "已复制报告 JSON"
    }
}
