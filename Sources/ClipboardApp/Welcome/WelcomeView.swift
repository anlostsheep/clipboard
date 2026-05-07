import AppKit
import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void

    @State private var isAuthorized = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("欢迎使用 Clipboard")
                    .font(.title.weight(.semibold))
                Text("Clipboard 运行在菜单栏中，随时通过快捷键或点击菜单栏图标访问剪贴板历史。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Label("辅助功能权限", systemImage: "hand.raised")
                    .font(.headline)

                Text("自动粘贴功能需要辅助功能权限，用于模拟 Command+V 按键。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    if isAuthorized {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("需要授权", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    if !isAuthorized {
                        Button("打开系统设置") {
                            openAccessibilitySettings()
                        }
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            HStack {
                Spacer()
                Button("开始使用") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAuthorized)
                .help(isAuthorized ? "" : "请先在系统设置中授权辅助功能权限")
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .onAppear { checkAuthorization() }
        .onReceive(timer) { _ in checkAuthorization() }
    }

    private func checkAuthorization() {
        isAuthorized = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
