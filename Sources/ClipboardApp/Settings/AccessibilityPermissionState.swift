import AppKit
import Combine

enum AccessibilityAuthorizationProbe {
    static let checkArgument = "--check-accessibility-trust"

    static func currentProcessTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    static func requestAuthorizationPrompt() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func settingsTrusted() -> Bool {
        resolve(
            currentProcessTrusted: currentProcessTrusted(),
            freshProcessTrusted: freshProcessTrusted()
        )
    }

    static func resolve(currentProcessTrusted: Bool, freshProcessTrusted: Bool?) -> Bool {
        freshProcessTrusted ?? currentProcessTrusted
    }

    static func freshProcessTrusted(executableURL: URL? = Bundle.main.executableURL) -> Bool? {
        guard let executableURL,
              !CommandLine.arguments.contains(checkArgument) else {
            return nil
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [checkArgument]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch output {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
}

@MainActor
final class AccessibilityPermissionState: ObservableObject {
    @Published private(set) var isAuthorized: Bool

    private let checkAuthorization: () -> Bool

    init(checkAuthorization: @escaping () -> Bool = { AccessibilityAuthorizationProbe.settingsTrusted() }) {
        self.checkAuthorization = checkAuthorization
        self.isAuthorized = checkAuthorization()
    }

    func refresh() {
        isAuthorized = checkAuthorization()
    }

    /// Triggers the macOS native accessibility prompt. The system dialog's
    /// "Open System Settings" button pre-populates this app in the Accessibility
    /// list, but the actual authorization state may change later in System Settings.
    func requestAuthorizationPrompt() {
        AccessibilityAuthorizationProbe.requestAuthorizationPrompt()
        refresh()
    }
}
