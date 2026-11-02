import XCTest

@testable import FlypeCore

final class KeyboardTypingRulesTests: XCTestCase {
    func testSentenceCapitalizationOnlyAtSentenceBoundaries() {
        for text in ["", "Hallo. ", "Wie geht es? ", "Super! ", "Absatz\n"] {
            XCTAssertTrue(KeyboardTypingRules.shouldUppercase(before: text, mode: .sentences))
        }
        for text in ["Hallo", "Hallo ", "Ein Wort, "] {
            XCTAssertFalse(KeyboardTypingRules.shouldUppercase(before: text, mode: .sentences))
        }
    }
    func testHostCapitalizationModesAreRespected() {
        XCTAssertFalse(KeyboardTypingRules.shouldUppercase(before: "", mode: .none))
        XCTAssertTrue(KeyboardTypingRules.shouldUppercase(before: "ein ", mode: .words))
        XCTAssertFalse(KeyboardTypingRules.shouldUppercase(before: "ein", mode: .words))
        XCTAssertTrue(KeyboardTypingRules.shouldUppercase(before: "klein", mode: .allCharacters))
    }
    func testDoubleSpaceDoesNotOverwritePunctuationOrBlankInput() {
        for text in ["", " ", "Hallo. ", "Hallo! ", "👋 "] {
            XCTAssertFalse(KeyboardTypingRules.canReplaceDoubleSpace(before: text))
        }
        for text in ["Hallo ", "Grüße ", "123 "] {
            XCTAssertTrue(KeyboardTypingRules.canReplaceDoubleSpace(before: text))
        }
    }
}
