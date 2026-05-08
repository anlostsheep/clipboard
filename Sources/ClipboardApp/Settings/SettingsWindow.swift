import ClipboardCore
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "通用"
    case privacy = "隐私"
    case history = "历史记录"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .privacy: return "hand.raised"
        case .history: return "clock"
        }
    }
}

struct SettingsRootView: View {
    let services: AppServices
    let hotKeyManager: HotKeyManager

    @State private var selectedPage: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedPage {
            case .general:
                GeneralSettingsView(hotKeyManager: hotKeyManager)
            case .privacy:
                PrivacySettingsView()
            case .history:
                HistorySettingsView(
                    services: services,
                    baseDirectory: try? ApplicationSupportPaths(
                        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.clipboard-manager"
                    ).baseDirectory
                )
            case nil:
                GeneralSettingsView(hotKeyManager: hotKeyManager)
            }
        }
        .navigationTitle(selectedPage?.rawValue ?? "设置")
    }
}
