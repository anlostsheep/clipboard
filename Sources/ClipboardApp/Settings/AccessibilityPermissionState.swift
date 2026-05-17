import AppKit
import Combine
import Security

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

enum CodeSignatureDiagnostics {
    private static let adHocSignatureFlag: UInt32 = 0x0002

    static func isCurrentProcessAdHocSigned() -> Bool {
        guard let flags = currentProcessSignatureFlags() else {
            return false
        }
        return isAdHocSigned(signatureFlags: flags)
    }

    static func isAdHocSigned(signatureFlags: UInt32) -> Bool {
        (signatureFlags & adHocSignatureFlag) != 0
    }

    private static func currentProcessSignatureFlags() -> UInt32? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
              let signingInformation = information as? [String: Any],
              let flags = signingInformation[kSecCodeInfoFlags as String] as? UInt32 else {
            return nil
        }

        return flags
    }
}

@MainActor
final class AccessibilityPermissionState: ObservableObject {
    @Published private(set) var isAuthorized: Bool
    let usesAdHocSignature: Bool

    private let checkAuthorization: () -> Bool

    init(
        checkAuthorization: @escaping () -> Bool = { AccessibilityAuthorizationProbe.settingsTrusted() },
        checkAdHocSignature: () -> Bool = { CodeSignatureDiagnostics.isCurrentProcessAdHocSigned() }
    ) {
        self.checkAuthorization = checkAuthorization
        self.usesAdHocSignature = checkAdHocSignature()
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
