import Foundation

/// Flype pastes into whatever has the keyboard focus, apart from password fields. Many apps, such as
/// browsers and Electron editors, do not report their text fields as such through accessibility.
public enum EditorInsertionPolicy {
    /// What Flype watches to notice a focus change: the reported text field, or else the window.
    public enum Anchor: Equatable, Sendable { case textElement, window }
    public static func anchor(focusedRole: String?, focusedSubrole: String?, secureInput: Bool) -> Anchor? {
        guard !secureInput, focusedSubrole != "AXSecureTextField" else { return nil }
        if let focusedRole, ["AXTextField", "AXTextArea", "AXComboBox"].contains(focusedRole) { return .textElement }
        return .window
    }
    /// Only a text field that still reads the same proves a failed paste. Rich editors may reformat
    /// the text, and other targets offer nothing to read.
    public static func pasteWasIgnored(anchor: Anchor, before: String?, after: String?) -> Bool {
        anchor == .textElement && before != nil && before == after
    }
    /// Confirm the exact UTF-16 replacement, including a selected range and non-BMP characters.
    public static func matchesExpectedInsertion(
        before: String, selection: NSRange, inserted: String, after: String
    ) -> Bool {
        let source = before as NSString
        guard !inserted.isEmpty, before != after, selection.location != NSNotFound,
            selection.location >= 0, selection.length >= 0, selection.location <= source.length,
            selection.length <= source.length - selection.location
        else { return false }
        return source.replacingCharacters(in: selection, with: inserted) == after
    }

}
