import AppKit
import ApplicationServices
import Carbon.HIToolbox
import FlypeCore

/// The focused text element, or the window of an app that does not report one.
@MainActor
struct TextDestination {
    let pid: pid_t
    let appName: String
    let anchor: AXUIElement
    let kind: EditorInsertionPolicy.Anchor

    /// Electron apps hide their text from assistive technology until asked. The request also makes the
    /// target build its accessibility tree, so it is only sent to the app the user is dictating into.
    static func exposeElectronText() {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, let bundle = app.bundleURL,
            FileManager.default.fileExists(
                atPath: bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        else { return }
        AXUIElementSetAttributeValue(
            AXUIElementCreateApplication(app.processIdentifier), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// The tree of an Electron app may only exist by the end of the recording, so the field can appear late.
    func refreshed() -> Self {
        guard kind != .textElement, let current = Self.capture().destination, current.pid == pid,
            current.kind == .textElement
        else { return self }
        return current
    }

    static func capture() -> (destination: Self?, problem: String?) {
        guard AXIsProcessTrusted() else { return (nil, "Bitte erlaube Flype die Bedienungshilfen unter Einrichtung.") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier
        else {
            return (nil, "Starte die Transkription mit dem Cursor in der App, in die dein Text eingefügt werden soll.")
        }
        guard !IsSecureEventInputEnabled() else {
            return (nil, "Geschützte Eingabe ist aktiv. Dein Text bleibt in Flype zum Kopieren bereit.")
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        let focused = element(application, kAXFocusedUIElementAttribute)
        guard
            let kind = EditorInsertionPolicy.anchor(
                focusedRole: string(focused, kAXRoleAttribute),
                focusedSubrole: string(focused, kAXSubroleAttribute), secureInput: false)
        else { return (nil, "Geschützte Eingabe ist aktiv. Dein Text bleibt in Flype zum Kopieren bereit.") }
        // Some apps expose neither a focused element nor a window until assistive technology asks them to.
        let anchor =
            (kind == .textElement ? focused : element(application, kAXFocusedWindowAttribute)) ?? application
        AXUIElementSetMessagingTimeout(anchor, 0.5)
        return (
            .init(pid: app.processIdentifier, appName: app.localizedName ?? "deine App", anchor: anchor, kind: kind),
            nil
        )
    }
    /// Tags our own paste events so shortcut monitoring does not mistake them for user edits.
    static let insertionEventTag: Int64 = 0x46_4C59_5045

    /// Nil means the paste was sent and nothing shows that the target ignored it.
    func insert(_ text: String) async -> String? {
        guard matchesCurrentFocus() else {
            return "Das Zieltextfeld hat sich geändert. Dein Text bleibt in Flype zum Kopieren bereit."
        }
        let before = Self.string(anchor, kAXValueAttribute)
        let selection = selectedRange()
        let board = NSPasteboard.general
        let previousCount = board.changeCount
        let previous = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        guard board.changeCount == previousCount, matchesCurrentFocus(), !Task.isCancelled,
            let source = CGEventSource(stateID: .combinedSessionState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return "Die Übergabe wurde unterbrochen. Dein vollständiger Text bleibt in Flype bereit." }
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            board.writeObjects(previous)
            return "Dieser Text konnte nicht automatisch übergeben werden. Bitte kopiere ihn aus Flype."
        }
        let pasteCount = board.changeCount
        defer {
            // A user's newer copy always takes precedence over restoring our temporary paste.
            if board.changeCount == pasteCount {
                board.clearContents()
                board.writeObjects(previous)
            }
        }
        guard matchesCurrentFocus(), !Task.isCancelled else {
            return "Das Zieltextfeld hat sich geändert. Dein Text bleibt in Flype zum Kopieren bereit."
        }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: Self.insertionEventTag)
            event.post(tap: .cgSessionEventTap)
        }
        // Give the target app time to process its normal Paste command before restoring the clipboard.
        for _ in 0..<30 {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
            guard matchesCurrentFocus() else { break }
            if let selection {
                if let before, let after = Self.string(anchor, kAXValueAttribute),
                    EditorInsertionPolicy.matchesExpectedInsertion(
                        before: before, selection: selection, inserted: text, after: after)
                {
                    return nil
                }
                if before == nil, let caret = selectedRange(), caret.length == 0,
                    caret.location == selection.location + text.utf16.count,
                    textAt(NSRange(location: selection.location, length: text.utf16.count)) == text
                {
                    return nil
                }
            }
            // Keep a lease for at least 1.5 seconds when a target provides no readable text.
        }
        let after = Self.string(anchor, kAXValueAttribute)
        guard EditorInsertionPolicy.pasteWasIgnored(anchor: kind, before: before, after: after) else { return nil }
        return "Das Einfügen konnte nicht bestätigt werden. Dein Text bleibt in Flype zum Kopieren bereit."
    }

    /// Only the end is read, so a dictation can continue a sentence that was started by typing.
    func textBeforeCursor() -> String? {
        guard kind == .textElement, matchesCurrentFocus(), let value = Self.string(anchor, kAXValueAttribute),
            let selection = selectedRange(), selection.location <= (value as NSString).length
        else { return nil }
        let text = (value as NSString).substring(to: selection.location)
        return text.isEmpty ? nil : DictationFieldContext.tail(of: text)
    }

    /// Only the start is read, so a dictation can end in the middle of a sentence that goes on after the cursor.
    func textAfterCursor() -> String? {
        guard kind == .textElement, matchesCurrentFocus(), let value = Self.string(anchor, kAXValueAttribute),
            let selection = selectedRange(), NSMaxRange(selection) <= (value as NSString).length
        else { return nil }
        let text = (value as NSString).substring(from: NSMaxRange(selection))
        return text.isEmpty ? nil : DictationFieldContext.head(of: text)
    }

    private func selectedRange() -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(anchor, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range), range.location >= 0, range.length >= 0 else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    private func textAt(_ range: NSRange) -> String? {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                anchor, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success
        else { return nil }
        return value as? String
    }
    private func matchesCurrentFocus() -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let current = Self.capture().destination
        else { return false }
        return kind == current.kind && CFEqual(anchor, current.anchor)
    }
    private static func element(_ owner: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }
    private static func string(_ owner: AXUIElement?, _ attribute: String) -> String? {
        guard let owner else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(owner, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
