import XCTest

@testable import FlypeCore

final class DictionaryCorrectionTests: XCTestCase {
    private let dictionary = DictionarySnapshot(entries: [.init(spelling: "Flype")])

    func testReportedFleibNeedsNoManualAliases() {
        let text = "Ich benutze Fleib."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.heard, "Fleib")
        let approved = DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: "Ich benutze Flype.")
        XCTAssertEqual(approved, [0])
        XCTAssertEqual(DictionaryCorrection.applying(candidates, approved: approved, to: text), "Ich benutze Flype.")
    }
    func testSimilarityAloneAndUnchangedAudioDoNotConfirm() {
        let text = "Ich benutze Fleib."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        XCTAssertTrue(DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: text).isEmpty)
        XCTAssertEqual(DictionaryCorrection.applying(candidates, approved: [], to: text), text)
    }
    func testOrdinarySentencesAndProtectedDataStayIntact() {
        for text in [
            "Ich bleibe hier.", "Bitte bleib bei mir.", "Der Leib ist müde.", "Ich benutze nicht 15 Euro.",
            "Mail an fleib@example.de", "https://fleib.de/path", "Fleib.de", "Superfleib Fleib-App",
        ] {
            XCTAssertTrue(DictionaryCorrection.candidates(in: text, dictionary: dictionary).isEmpty, text)
        }
    }
    func testChangedNegationNumberOrDifferentSentenceCannotConfirm() {
        let text = "Ich benutze Fleib nicht für 15 Euro."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        for evidence in ["Ich benutze Flype für 15 Euro.", "Ich benutze Flype nicht für 50 Euro.", "Du benutzt Flype."]
        {
            XCTAssertTrue(DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: evidence).isEmpty)
        }
    }
    func testApproximateSecondRecognitionNeedsExplicitContextGate() {
        let text = "Ich benutze Fleib."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        XCTAssertTrue(
            DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: "Ich benutze Flight.").isEmpty)
        XCTAssertEqual(
            DictionaryCorrection.audioConfirmed(
                candidates, original: text, evidence: "Ich benutze Flight.", allowPhonetic: true), [0])
        XCTAssertTrue(
            DictionaryCorrection.audioConfirmed(
                candidates, original: text, evidence: "Ich benutze Blei.", allowPhonetic: true
            ).isEmpty)
        XCTAssertTrue(
            DictionaryCorrection.audioConfirmed(
                candidates, original: text, evidence: "Ich benutze Flight nicht.", allowPhonetic: true
            ).isEmpty)
    }
    func testTwoRecognizersCanAgreeOnASimilarButWrongSpelling() {
        let text = "Ich benutze Flight."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertTrue(DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: text).isEmpty)
        XCTAssertEqual(
            DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: text, allowPhonetic: true), [0])
    }
    func testContextRejectionAndInventedIDsLeaveOriginalUntouched() {
        let text = "Ich benutze Fleib."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        var approved = DictionaryCorrection.audioConfirmed(
            candidates, original: text, evidence: "Ich benutze Flight.", allowPhonetic: true)
        approved.formIntersection([999])
        XCTAssertEqual(DictionaryCorrection.applying(candidates, approved: approved, to: text), text)
    }
    func testRepeatedOccurrencesMustAlignToTheirActualPosition() {
        let text = "Fleib und Fleib"
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        let ids = DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: "Flype und Fleib")
        XCTAssertEqual(ids, [0])
        XCTAssertEqual(DictionaryCorrection.applying(candidates, approved: ids, to: text), "Flype und Fleib")
        let both = DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: "Flype und Flype")
        XCTAssertEqual(both, [0, 1])
    }
    func testDisabledAndTypingOnlyEntriesAreExcluded() {
        let off = DictionarySnapshot(entries: [.init(spelling: "Flype", enabled: false)])
        let typing = DictionarySnapshot(entries: [.init(spelling: "Flype", useForDictation: false)])
        XCTAssertTrue(DictionaryCorrection.candidates(in: "Fleib", dictionary: off).isEmpty)
        XCTAssertTrue(DictionaryCorrection.candidates(in: "Fleib", dictionary: typing).isEmpty)
    }
    func testUnicodeAndPunctuationArePreservedByBoundedEdits() {
        let text = "👋 Ich benutze Fleib, für Müller."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        let ids = DictionaryCorrection.audioConfirmed(
            candidates, original: text, evidence: "Ich benutze Flype für Müller")
        XCTAssertEqual(
            DictionaryCorrection.applying(candidates, approved: ids, to: text), "👋 Ich benutze Flype, für Müller.")
    }
    func testMultiwordTermsKeepTheirBounds() {
        let dict = DictionarySnapshot(entries: [.init(spelling: "Flype Studio")])
        let text = "Ich benutze Fleib Studio."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dict)
        let ids = DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: "Ich benutze Flype Studio.")
        XCTAssertEqual(DictionaryCorrection.applying(candidates, approved: ids, to: text), "Ich benutze Flype Studio.")
    }
    func testAmbiguousDuplicateCandidatesDoNotForceAnEdit() {
        let dict = DictionarySnapshot(entries: [.init(spelling: "Flype"), .init(spelling: "FLYPE")])
        let text = "Fleib"
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dict)
        XCTAssertTrue(DictionaryCorrection.audioConfirmed(candidates, original: text, evidence: "Flype").isEmpty)
    }
    func testInvalidOrOverlappingModelDecisionsCannotChangeOtherText() {
        let text = "Ich benutze Fleib."
        let candidates = DictionaryCorrection.candidates(in: text, dictionary: dictionary)
        XCTAssertEqual(DictionaryCorrection.applying(candidates, approved: [999], to: text), text)
        XCTAssertEqual(
            DictionaryCorrection.applying(candidates, approved: [0], to: "Ein anderer Text"), "Ein anderer Text")
        XCTAssertEqual(DictionaryCorrection.applying(candidates + candidates, approved: [0], to: text), text)
    }
    func testNamesCannotIntroduceNumbersOrPunctuation() {
        for spelling in ["Flype15", "Flype!", "Flype 👋"] {
            let dict = DictionarySnapshot(entries: [.init(spelling: spelling)])
            XCTAssertTrue(DictionaryCorrection.candidates(in: "Fleib", dictionary: dict).isEmpty)
        }
    }
    func testInputAndCandidateBudgetsAreBounded() {
        XCTAssertTrue(
            DictionaryCorrection.candidates(in: String(repeating: "Fleib ", count: 1_000), dictionary: dictionary)
                .isEmpty)
        XCTAssertEqual(
            DictionaryCorrection.candidates(in: String(repeating: "Fleib ", count: 100), dictionary: dictionary).count,
            12)
    }
}

extension DictionaryCorrectionTests {
    func testOnlyUndecidedCandidatesWithAudioSupportBecomeSoundAlikes() {
        let candidates = [
            DictionaryCandidate(id: 0, range: NSRange(location: 0, length: 5), heard: "Fleip", spelling: "Flype"),
            DictionaryCandidate(id: 1, range: NSRange(location: 6, length: 5), heard: "Muster", spelling: "Mustr"),
            DictionaryCandidate(id: 2, range: NSRange(location: 12, length: 5), heard: "Klara", spelling: "Clara"),
            DictionaryCandidate(id: 3, range: NSRange(location: 20, length: 5), heard: "Fleip", spelling: "Flype"),
        ]
        let hints = DictionaryCorrection.soundAlikes(candidates, audioSupported: [0, 2, 3], decided: [2])
        XCTAssertEqual(hints, [DictionarySoundAlike(heard: "Fleip", spelling: "Flype")])
        XCTAssertTrue(DictionaryCorrection.soundAlikes(candidates, audioSupported: [], decided: []).isEmpty)
    }
}
