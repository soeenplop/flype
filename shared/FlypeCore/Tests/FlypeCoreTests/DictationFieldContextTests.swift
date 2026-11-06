import Foundation
import XCTest

@testable import FlypeCore

final class DictationFieldContextTests: XCTestCase {
    private func store() -> DictationFieldContextStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return DictationFieldContextStore(directory: directory)
    }
    func testOnlyTheEndOfTheFieldIsKept() {
        let context = DictationFieldContext(
            requestID: UUID(), text: "Anfang " + String(repeating: "ä", count: 200))
        XCTAssertEqual(context.text, String(repeating: "ä", count: 200))
    }
    func testASpaceIsAddedOnlyWhereTheFieldEndsAtAWordOrSentence() {
        for (context, text, expected) in [
            ("Das", "klappt", " "), ("Das ist gut.", "Morgen", " "), ("Das ", "klappt", ""),
            ("Das\n", "klappt", ""), ("", "klappt", ""), (nil, "klappt", ""),
            ("Das", ", und", ""), ("Das", ".", ""), ("(", "klappt", ""), ("„", "klappt", ""),
        ] as [(String?, String, String)] {
            XCTAssertEqual(
                DictationFieldContext.separator(before: text, after: context), expected, "\(context ?? "nil")")
        }
    }
    func testTheMatchingDictationReadsTheContextOnce() throws {
        let store = store()
        let id = UUID()
        try store.save(DictationFieldContext(requestID: id, text: "Ich gehe heute"))
        XCTAssertEqual(store.take(requestID: id)?.text, "Ich gehe heute")
        XCTAssertNil(store.take(requestID: id))
    }
    func testTheTextAfterTheCursorIsKeptFromItsStart() throws {
        let store = store()
        let id = UUID()
        let following = "zum Essen." + String(repeating: "ä", count: 200)
        try store.save(DictationFieldContext(requestID: id, text: "", following: following))
        let context = try XCTUnwrap(store.take(requestID: id))
        XCTAssertEqual(context.text, "")
        XCTAssertEqual(context.following, String(following.prefix(200)))
        XCTAssertNil(DictationFieldContext(requestID: id, text: "Das").following)
    }
    func testAContextFromAnOlderKeyboardStillReads() throws {
        let id = UUID()
        let data = Data(#"{"requestID":"\#(id.uuidString)","text":"Das","createdAt":0}"#.utf8)
        let context = try JSONDecoder().decode(DictationFieldContext.self, from: data)
        XCTAssertEqual(context.text, "Das")
        XCTAssertNil(context.following)
    }
    func testTheSpaceAfterADictationDependsOnTheFollowingText() {
        for (following, expected) in [
            (nil, " "), ("", " "), ("zum Essen.", " "), (" zum Essen.", ""), ("\nNeu", ""), (", wenn", ""),
            (".", ""),
        ] as [(String?, String)] {
            XCTAssertEqual(
                DictationFieldContext.trailingSeparator(after: "morgen", following: following), expected,
                "\(following ?? "nil")")
        }
    }
    func testAnotherDictationCannotReadItAndNothingStays() throws {
        let store = store()
        let id = UUID()
        try store.save(DictationFieldContext(requestID: id, text: "Ich gehe heute"))
        XCTAssertNil(store.take(requestID: UUID()))
        XCTAssertNil(store.take(requestID: id))
    }
    func testOldContextExpiresAndAnEmptyFieldClearsAnOlderOne() throws {
        let store = store()
        let id = UUID()
        try store.save(DictationFieldContext(requestID: id, text: "alt", createdAt: Date().addingTimeInterval(-601)))
        XCTAssertNil(store.take(requestID: id))
        try store.save(DictationFieldContext(requestID: id, text: "alt"))
        try store.save(DictationFieldContext(requestID: id, text: ""))
        XCTAssertNil(store.take(requestID: id))
    }
}
