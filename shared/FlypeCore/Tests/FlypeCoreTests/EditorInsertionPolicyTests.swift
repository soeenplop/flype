import XCTest

@testable import FlypeCore

final class EditorInsertionPolicyTests: XCTestCase {
    func testReportedTextFieldsAreWatchedDirectly() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            XCTAssertEqual(
                EditorInsertionPolicy.anchor(focusedRole: role, focusedSubrole: nil, secureInput: false), .textElement)
        }
    }
    func testEveryOtherFocusStillReceivesDictation() {
        for role in ["AXWebArea", "AXGroup", "AXWindow", "AXButton", nil] as [String?] {
            XCTAssertEqual(
                EditorInsertionPolicy.anchor(focusedRole: role, focusedSubrole: nil, secureInput: false), .window)
        }
    }
    func testSecureInputCannotUseEitherInsertionPath() {
        XCTAssertNil(EditorInsertionPolicy.anchor(focusedRole: "AXWebArea", focusedSubrole: nil, secureInput: true))
        XCTAssertNil(EditorInsertionPolicy.anchor(focusedRole: nil, focusedSubrole: nil, secureInput: true))
        XCTAssertNil(
            EditorInsertionPolicy.anchor(
                focusedRole: "AXTextField", focusedSubrole: "AXSecureTextField", secureInput: false))
    }
    func testOnlyAnUnchangedTextFieldCountsAsAnIgnoredPaste() {
        XCTAssertTrue(EditorInsertionPolicy.pasteWasIgnored(anchor: .textElement, before: "a", after: "a"))
        XCTAssertFalse(EditorInsertionPolicy.pasteWasIgnored(anchor: .textElement, before: "a", after: "a b"))
        XCTAssertFalse(EditorInsertionPolicy.pasteWasIgnored(anchor: .textElement, before: nil, after: nil))
        XCTAssertFalse(EditorInsertionPolicy.pasteWasIgnored(anchor: .window, before: "a", after: "a"))
    }
    func testInsertionIsConfirmedOnlyByTheExactChangedText() {
        XCTAssertTrue(
            EditorInsertionPolicy.matchesExpectedInsertion(
                before: "Hallo ", selection: NSRange(location: 6, length: 0), inserted: "Anna ", after: "Hallo Anna "))
        XCTAssertTrue(
            EditorInsertionPolicy.matchesExpectedInsertion(
                before: "Hallo Welt", selection: NSRange(location: 6, length: 4), inserted: "Anna", after: "Hallo Anna")
        )
        XCTAssertFalse(
            EditorInsertionPolicy.matchesExpectedInsertion(
                before: "Hallo Anna", selection: NSRange(location: 0, length: 0), inserted: "Anna", after: "Hallo Anna")
        )
        XCTAssertFalse(
            EditorInsertionPolicy.matchesExpectedInsertion(
                before: "Hallo Welt", selection: NSRange(location: 6, length: 4), inserted: "Anna",
                after: "Anna Hallo Welt"))
    }

    func testInsertionVerificationUsesUTF16AndRejectsStaleRanges() {
        let original = "Hallo 🌍!"
        XCTAssertTrue(
            EditorInsertionPolicy.matchesExpectedInsertion(
                before: original, selection: (original as NSString).range(of: "🌍"), inserted: "Anna 👋",
                after: "Hallo Anna 👋!"))
        for range in [
            NSRange(location: NSNotFound, length: 0), NSRange(location: 50, length: 0),
            NSRange(location: 2, length: 50),
        ] {
            XCTAssertFalse(
                EditorInsertionPolicy.matchesExpectedInsertion(
                    before: original, selection: range, inserted: "Test", after: "Test"))
        }
    }

}
