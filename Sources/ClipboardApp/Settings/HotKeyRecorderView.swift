import AppKit
import Carbon
import ClipboardCore
import SwiftUI

struct HotKeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onConflict: (String) -> Void

    @State private var isRecording = false

    var displayText: String {
        if isRecording { return "录制中…按下快捷键" }
        return Self.humanReadable(keyCode: keyCode, modifiers: modifiers)
    }

    var body: some View {
        HStack {
            Text(displayText)
                .frame(minWidth: 160, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                .onTapGesture { isRecording = true }

            if isRecording {
                Button("取消") { isRecording = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .background(
            KeyRecordingNSView(
                isRecording: isRecording,
                onKeyDown: { kc, mods in
                    handleKeyDown(keyCode: kc, modifiers: mods)
                }
            ).frame(width: 0, height: 0)
        )
    }

    private func handleKeyDown(keyCode: UInt32, modifiers: UInt32) {
        if HotKeyConflictDetector.isSystemBlacklisted(keyCode: keyCode, modifiers: modifiers) {
            onConflict("该快捷键为系统保留，请选择其他组合")
            isRecording = false
            return
        }
        self.keyCode = keyCode
        self.modifiers = modifiers
        isRecording = false
        ClipboardAppSettings.saveHotkey(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Human-readable display

    static func humanReadable(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        let m = modifiers
        if m & UInt32(controlKey) != 0 { parts.append("⌃") }
        if m & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if m & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if m & UInt32(cmdKey)     != 0 { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_ANSI_A: keyName = "A"
        case kVK_ANSI_B: keyName = "B"
        case kVK_ANSI_C: keyName = "C"
        case kVK_ANSI_D: keyName = "D"
        case kVK_ANSI_E: keyName = "E"
        case kVK_ANSI_F: keyName = "F"
        case kVK_ANSI_G: keyName = "G"
        case kVK_ANSI_H: keyName = "H"
        case kVK_ANSI_I: keyName = "I"
        case kVK_ANSI_J: keyName = "J"
        case kVK_ANSI_K: keyName = "K"
        case kVK_ANSI_L: keyName = "L"
        case kVK_ANSI_M: keyName = "M"
        case kVK_ANSI_N: keyName = "N"
        case kVK_ANSI_O: keyName = "O"
        case kVK_ANSI_P: keyName = "P"
        case kVK_ANSI_Q: keyName = "Q"
        case kVK_ANSI_R: keyName = "R"
        case kVK_ANSI_S: keyName = "S"
        case kVK_ANSI_T: keyName = "T"
        case kVK_ANSI_U: keyName = "U"
        case kVK_ANSI_V: keyName = "V"
        case kVK_ANSI_W: keyName = "W"
        case kVK_ANSI_X: keyName = "X"
        case kVK_ANSI_Y: keyName = "Y"
        case kVK_ANSI_Z: keyName = "Z"
        case kVK_F1:  keyName = "F1"
        case kVK_F2:  keyName = "F2"
        case kVK_F3:  keyName = "F3"
        case kVK_F4:  keyName = "F4"
        case kVK_F5:  keyName = "F5"
        case kVK_F6:  keyName = "F6"
        case kVK_F7:  keyName = "F7"
        case kVK_F8:  keyName = "F8"
        case kVK_F9:  keyName = "F9"
        case kVK_F10: keyName = "F10"
        case kVK_F11: keyName = "F11"
        case kVK_F12: keyName = "F12"
        default: keyName = "Key(\(keyCode))"
        }
        parts.append(keyName)
        return parts.joined()
    }
}

// MARK: - NSViewRepresentable bridge for capturing raw key events

private struct KeyRecordingNSView: NSViewRepresentable {
    let isRecording: Bool
    let onKeyDown: (UInt32, UInt32) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onKeyDown: onKeyDown) }

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        if isRecording {
            context.coordinator.installMonitor()
        } else {
            context.coordinator.removeMonitor()
        }
    }

    static func dismantleNSView(_ nsView: RecorderNSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
        coordinator.view = nil
    }

    final class Coordinator {
        var onKeyDown: (UInt32, UInt32) -> Void
        weak var view: RecorderNSView?
        private var monitor: Any?

        init(onKeyDown: @escaping (UInt32, UInt32) -> Void) {
            self.onKeyDown = onKeyDown
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.view?.window != nil else { return event }
                var mods: UInt32 = 0
                let flags = event.modifierFlags
                if flags.contains(.command) { mods |= UInt32(cmdKey) }
                if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
                if flags.contains(.option)  { mods |= UInt32(optionKey) }
                if flags.contains(.control) { mods |= UInt32(controlKey) }
                self.onKeyDown(UInt32(event.keyCode), mods)
                return nil
            }
        }

        func removeMonitor() {
            guard let m = monitor else { return }
            NSEvent.removeMonitor(m)
            monitor = nil
        }

        deinit { removeMonitor() }
    }
}

final class RecorderNSView: NSView {}
