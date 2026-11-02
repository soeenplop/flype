import XCTest

@testable import FlypeCore

final class PersonalDictionaryTests: XCTestCase {
    private func store() -> PersonalDictionaryStore {
        PersonalDictionaryStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    func testPersistsUpdatesAndDeletesWithNewRevision() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        var entry = PersonalDictionaryEntry(spelling: "Flype", aliases: ["flaip"])
        try store.upsert(entry)
        let original = try store.snapshot()
        XCTAssertEqual(original.entries, [entry])
        entry.enabled = false
        try store.upsert(entry)
        XCTAssertNotEqual(try store.snapshot().revision, original.revision)
        XCTAssertEqual(try store.snapshot().entries.count, 1)
        try store.delete(id: entry.id)
        XCTAssertTrue(try store.snapshot().entries.isEmpty)
    }
    func testNormalizesUnicodeAndRejectsCollidingAliases() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.upsert(PersonalDictionaryEntry(spelling: "  Mu\u{0308}ller  ", aliases: ["Miller"]))
        XCTAssertEqual(try store.snapshot().entries.first?.spelling, "Müller")
        XCTAssertThrowsError(try store.upsert(PersonalDictionaryEntry(spelling: "Anders", aliases: ["miller"])))
        XCTAssertThrowsError(try store.upsert(PersonalDictionaryEntry(spelling: "Müller")))
        XCTAssertThrowsError(try store.upsert(PersonalDictionaryEntry(spelling: "")))
    }
    func testNoImplicitDictationReplacementOrSubstringReplacement() {
        let off = DictionarySnapshot(entries: [.init(spelling: "Flype", aliases: ["Flaip"])])
        XCTAssertEqual(off.applyingAliases(to: "Flaip ist gut."), "Flaip ist gut.")
        let on = DictionarySnapshot(entries: [.init(spelling: "Flype", aliases: ["Flaip"], replaceAliases: true)])
        XCTAssertEqual(
            on.applyingAliases(to: "Flaip, flaip! Nicht Superflaip oder Flaip-App."),
            "Flype, Flype! Nicht Superflaip oder Flaip-App.")
    }
    func testSharpSIsNotSilentlyTreatedAsDoubleS() {
        let snapshot = DictionarySnapshot(entries: [.init(spelling: "Messung", aliases: ["Maße"], replaceAliases: true)]
        )
        XCTAssertEqual(snapshot.applyingAliases(to: "Maße und Masse"), "Messung und Masse")
        let unicode = DictionarySnapshot(entries: [
            .init(spelling: "Müller GmbH", aliases: ["Müller"], replaceAliases: true)
        ])
        XCTAssertEqual(unicode.applyingAliases(to: "Mu\u{0308}ller kommt"), "Müller GmbH kommt")
    }
    func testReplacementIsOnePassWithPhrasesAndUnicodeRanges() {
        let snapshot = DictionarySnapshot(entries: [
            .init(spelling: "Flype", aliases: ["fly app"], replaceAliases: true),
            .init(spelling: "Andere", aliases: ["Flype"], replaceAliases: true),
        ])
        XCTAssertEqual(snapshot.applyingAliases(to: "👋 fly app und fly app."), "👋 Flype und Flype.")
    }
    func testTypingAndDictationFlagsAreIndependentAndPreserveCase() {
        let snapshot = DictionarySnapshot(entries: [
            .init(spelling: "iPhone"), .init(spelling: "iPad", enabled: false),
            .init(spelling: "iCloud", useForTyping: false), .init(spelling: "iOS", useForDictation: false),
            .init(spelling: "i Phone"),
        ])
        XCTAssertEqual(Set(snapshot.completions(prefix: "i")), Set(["iPhone", "iOS"]))
        XCTAssertEqual(snapshot.relevantTerms(for: "iPhone iOS"), ["iPhone"])
        XCTAssertTrue(snapshot.completions(prefix: "").isEmpty)
    }
    func testCorruptOrFutureDataCannotOverwriteDictionary() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.upsert(.init(spelling: "Flype"))
        var snapshot = try store.snapshot()
        snapshot.schemaVersion = 99
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: store.fileURL)
        XCTAssertThrowsError(try store.snapshot())
        XCTAssertThrowsError(try store.upsert(.init(spelling: "Neu")))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), data)
        try Data("corrupt".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.snapshot())
    }
    func testConcurrentWritersDoNotLoseEntries() throws {
        let store = store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do { try store.upsert(.init(spelling: "Begriff\(index)")) } catch { XCTFail("Concurrent write failed") }
        }
        XCTAssertEqual(try store.snapshot().entries.count, 20)
    }
}
