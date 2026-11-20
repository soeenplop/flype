import Foundation
import XCTest

@testable import FlypeCore

final class WordSuggestionContextTests: XCTestCase {
    func testGermanUmlautsAndSharpSStayInWord() {
        let context = WordSuggestionContext(before: "Die Straß", after: "en sind frei.")
        XCTAssertEqual(context.prefix, "Straß")
        XCTAssertEqual(context.suffix, "en")
        XCTAssertEqual(context.word, "Straßen")
        XCTAssertEqual(context.replacementCount, 7)
        XCTAssertEqual(context.precedingWord, "die")
    }
    func testMidWordReplacementUsesWholeWordButNotPunctuation() {
        let context = WordSuggestionContext(before: "Hallo, mor", after: "gen!")
        XCTAssertEqual(context.word, "morgen")
        XCTAssertEqual(context.replacementCount, 6)
        XCTAssertEqual(context.precedingWord, "hallo")
    }
    func testEmojiAndWhitespaceDoNotBecomePartOfWord() {
        let context = WordSuggestionContext(before: "👨‍👩‍👧 Hallo ", after: "")
        XCTAssertEqual(context.word, "")
        XCTAssertEqual(context.replacementCount, 0)
        XCTAssertEqual(context.precedingWord, "hallo")
    }
    func testLetterLikeEmojiEndsWord() {
        let context = WordSuggestionContext(before: "hiℹ️cat", after: "")
        XCTAssertEqual(context.prefix, "cat")
        XCTAssertEqual(context.replacementCount, 3)
        XCTAssertEqual(context.precedingWord, "hi")
        XCTAssertFalse(SwipeCorrection.isWordCharacter("ℹ️"))
        XCTAssertTrue(SwipeCorrection.isWordCharacter("ℹ"))
        XCTAssertTrue(SwipeCorrection.isWordCharacter("ß"))
    }
    func testApostrophesAndComposedCharactersUseCharacterDeletionCounts() {
        let context = WordSuggestionContext(before: "ich gru\u{0308}", after: "ße")
        XCTAssertEqual(context.replacementCount, 5)
        XCTAssertEqual(context.word, "gru\u{0308}ße")
        XCTAssertEqual(WordSuggestionContext(before: "geht’", after: "s?").word, "geht’s")
    }
}
