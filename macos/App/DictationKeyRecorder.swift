import AppKit
import Carbon.HIToolbox
import FlypeCore
import SwiftUI

extension DictationKey {
    /// Large label for the key, without the side of a modifier.
    var symbol: String {
        switch keyCode {
        case 54, 55: "⌘"
        case 56, 60: "⇧"
        case 58, 61: "⌥"
        case 59, 62: "⌃"
        case 63: "fn"
        case 36: "↩"
        case 48: "⇥"
        case 49: "␣"
        case 51: "⌫"
        case 76: "⌅"
        case 115: "↖"
        case 116: "⇞"
        case 117: "⌦"
        case 119: "↘"
        case 121: "⇟"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default: functionKeyName ?? typedCharacter ?? "#\(keyCode)"
        }
    }
    var side: String? {
        switch keyCode {
        case 54, 60, 61, 62: "rechts"
        case 55, 56, 58, 59: "links"
        default: nil
        }
    }
    /// Reads the same within a sentence in every language.
    var name: String {
        if let side { return symbol + " " + L10n.text(side) }
        return keyCode == 49 ? L10n.text("Leertaste") : symbol
    }
    private var functionKeyName: String? {
        let keys: [UInt16: Int] = [
            122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12, 105: 13,
            107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
        ]
        return keys[keyCode].map { "F\($0)" }
    }
    /// What this key writes on the current keyboard layout.
    private var typedCharacter: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layout.withUnsafeBytes { bytes -> OSStatus in
            guard let data = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                data, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text.uppercased()
    }
}

/// Waits for one key after a click and stores it. Modifiers count the moment they go down.
struct DictationKeyRecorder: View {
    @Binding var keyCode: Int
    let onRecording: (Bool) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        Button {
            if recording { stop() } else { start() }
        } label: {
            Text(recording ? L10n.text("Taste drücken …") : (DictationKey(keyCode: keyCode) ?? .rightCommand).name)
                .frame(minWidth: 130)
        }
        .tint(recording ? FlypeDesign.accent : nil)
        .onDisappear { stop() }
    }
    private func start() {
        recording = true
        onRecording(true)
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handle(event) }
        }
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            stop()
            return event
        case .flagsChanged:
            guard let key = DictationKey(keyCode: Int(event.keyCode)), key.isModifier, isPressed(event) else {
                return nil
            }
            save(key)
            return nil
        default:
            if event.keyCode == 53 {
                stop()
            } else if !event.isARepeat, let key = DictationKey(keyCode: Int(event.keyCode)) {
                save(key)
            }
            return nil
        }
    }
    /// A flags change also reports a modifier going up.
    private func isPressed(_ event: NSEvent) -> Bool {
        let flag: NSEvent.ModifierFlags =
            switch event.keyCode {
            case 54, 55: .command
            case 56, 60: .shift
            case 58, 61: .option
            case 59, 62: .control
            default: .function
            }
        return event.modifierFlags.contains(flag)
    }
    private func save(_ key: DictationKey) {
        keyCode = Int(key.keyCode)
        stop()
    }
    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        onRecording(false)
    }
}
