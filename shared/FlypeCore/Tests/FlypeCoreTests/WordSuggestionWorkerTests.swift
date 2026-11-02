import Foundation
import XCTest

@testable import FlypeCore

@MainActor
final class WordSuggestionWorkerTests: XCTestCase {
    func testDictionaryKeepsBrandSpellingAndPrecedesSystemResults() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalDictionaryStore(directory: directory)
        try store.upsert(PersonalDictionaryEntry(spelling: "Flype"))
        try store.upsert(PersonalDictionaryEntry(spelling: "Flyper", useForTyping: false))
        let worker = WordSuggestionWorker(store: store)
        let result = await worker.candidates(
            for: WordSuggestionContext(before: "FLY", after: ""), language: .de,
            systemCandidates: ["flype", "flying", "flyer"], dictionaryEnabled: true)
        XCTAssertEqual(result, ["FLY", "Flype", "FLYING"])
    }

    func testDisablingDictionaryDropsCachedEntriesAndReenablingReloads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalDictionaryStore(directory: directory)
        let entry = PersonalDictionaryEntry(spelling: "Flype")
        try store.upsert(entry)
        let worker = WordSuggestionWorker(store: store)
        let context = WordSuggestionContext(before: "fly", after: "")
        let enabled = await worker.candidates(
            for: context, language: .de, systemCandidates: [], dictionaryEnabled: true)
        XCTAssertEqual(enabled, ["fly", "Flype"])
        let disabled = await worker.candidates(
            for: context, language: .de, systemCandidates: [], dictionaryEnabled: false)
        XCTAssertEqual(disabled, ["fly"])
        try store.delete(id: entry.id)
        try store.upsert(PersonalDictionaryEntry(spelling: "Flywheel"))
        let reenabled = await worker.candidates(
            for: context, language: .de, systemCandidates: [], dictionaryEnabled: true)
        XCTAssertEqual(reenabled, ["fly", "Flywheel"])
    }

    func testWithoutFullAccessDoesNotCreateDictionaryFiles() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let worker = WordSuggestionWorker(store: PersonalDictionaryStore(directory: directory))
        _ = await worker.candidates(
            for: WordSuggestionContext(before: "h", after: ""), language: .de,
            systemCandidates: ["hallo"], dictionaryEnabled: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testCanonicalDuplicatesAndCapitalization() async {
        let worker = WordSuggestionWorker()
        let result = await worker.candidates(
            for: WordSuggestionContext(before: "Grü", after: ""), language: .de,
            systemCandidates: ["grü", "gru\u{0308}ße", "grüße", "grün"], dictionaryEnabled: false)
        XCTAssertEqual(result, ["Grü", "Gru\u{0308}ße", "Grün"])
    }

    func testLanguageDefaultsAndMidWordBoundary() async {
        let worker = WordSuggestionWorker()
        for language in FlypeLanguage.allCases {
            let result = await worker.candidates(
                for: WordSuggestionContext(before: "Hallo. ", after: ""), language: language,
                systemCandidates: [], dictionaryEnabled: false)
            XCTAssertEqual(result, language.startingWords)
        }
        let insideWord = await worker.candidates(
            for: WordSuggestionContext(before: "", after: "Hallo"), language: .de,
            systemCandidates: [], dictionaryEnabled: false)
        XCTAssertTrue(insideWord.isEmpty)
    }
}
