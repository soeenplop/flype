import XCTest

@testable import FlypeCore

final class DictationShortcutTests: XCTestCase {
    func testHoldStartsOnceAndReleaseFinishes() {
        var shortcut = DictationShortcut()
        XCTAssertEqual(shortcut.update(keyDown: true, otherModifier: false, now: 0), .armed)
        XCTAssertNil(shortcut.advance(now: 0.1))
        XCTAssertEqual(shortcut.advance(now: 0.2), .started)
        XCTAssertNil(shortcut.advance(now: 2))
        XCTAssertEqual(shortcut.update(keyDown: false, otherModifier: false, now: 4), .finished)
        XCTAssertNil(shortcut.advance(now: 5))
    }
    func testQuickTapArmsAudioButCancelsInsteadOfTranscribing() {
        var shortcut = DictationShortcut()
        XCTAssertEqual(shortcut.update(keyDown: true, otherModifier: false, now: 0), .armed)
        XCTAssertEqual(shortcut.update(keyDown: false, otherModifier: false, now: 0.08), .cancelled)
        XCTAssertNil(shortcut.advance(now: 0.3))
    }
    func testCommandShortcutBeforeThresholdDiscardsArmedAudio() {
        var shortcut = DictationShortcut()
        _ = shortcut.update(keyDown: true, otherModifier: false, now: 0)
        XCTAssertEqual(shortcut.interrupt(), .cancelled)
        XCTAssertNil(shortcut.advance(now: 0.3))
        XCTAssertNil(shortcut.update(keyDown: false, otherModifier: false, now: 1))
    }
    func testCommandShortcutDuringRecordingCancelsInsteadOfInserting() {
        var shortcut = DictationShortcut()
        _ = shortcut.update(keyDown: true, otherModifier: false, now: 0)
        XCTAssertEqual(shortcut.advance(now: 0.2), .started)
        XCTAssertEqual(shortcut.interrupt(), .cancelled)
        XCTAssertNil(shortcut.advance(now: 1))
        XCTAssertNil(shortcut.update(keyDown: false, otherModifier: false, now: 2))
    }
    func testOtherModifierBlocksUntilRightCommandReleased() {
        var shortcut = DictationShortcut()
        _ = shortcut.update(keyDown: true, otherModifier: false, now: 0)
        XCTAssertEqual(shortcut.update(keyDown: true, otherModifier: true, now: 0.1), .cancelled)
        XCTAssertNil(shortcut.update(keyDown: true, otherModifier: false, now: 0.2))
        XCTAssertNil(shortcut.advance(now: 1))
        XCTAssertNil(shortcut.update(keyDown: false, otherModifier: false, now: 2))
        _ = shortcut.update(keyDown: true, otherModifier: false, now: 3)
        XCTAssertEqual(shortcut.advance(now: 3.2), .started)
    }
    func testHeldOtherModifierCannotArmShortcut() {
        var shortcut = DictationShortcut()
        XCTAssertNil(shortcut.update(keyDown: true, otherModifier: true, now: 0))
        XCTAssertNil(shortcut.update(keyDown: true, otherModifier: false, now: 1))
        XCTAssertNil(shortcut.advance(now: 2))
        XCTAssertNil(shortcut.update(keyDown: false, otherModifier: false, now: 3))
    }
    func testRepeatedFlagsDoNotRestartHoldTimer() {
        var shortcut = DictationShortcut()
        _ = shortcut.update(keyDown: true, otherModifier: false, now: 0)
        XCTAssertNil(shortcut.update(keyDown: true, otherModifier: false, now: 0.1))
        XCTAssertEqual(shortcut.advance(now: 0.2), .started)
        XCTAssertNil(shortcut.update(keyDown: true, otherModifier: false, now: 1))
        XCTAssertEqual(shortcut.update(keyDown: false, otherModifier: false, now: 2), .finished)
    }
    func testLongHoldIsNotLimitedByOldTapThreshold() {
        var shortcut = DictationShortcut()
        _ = shortcut.update(keyDown: true, otherModifier: false, now: 0)
        XCTAssertEqual(shortcut.advance(now: 0.2), .started)
        XCTAssertEqual(shortcut.update(keyDown: false, otherModifier: false, now: 60), .finished)
    }
}
