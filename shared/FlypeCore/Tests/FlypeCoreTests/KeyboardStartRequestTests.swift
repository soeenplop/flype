import Foundation
import XCTest

@testable import FlypeCore

final class KeyboardStartRequestTests: XCTestCase {
    func testOnlyExpectedURLIsAccepted() {
        let request = KeyboardStartRequest()
        XCTAssertEqual(KeyboardStartRequest.requestID(from: request.url), request.id)
        for value in [
            "flype://dictate", "flype://dictate?request=bad", "https://dictate?request=\(request.id)",
            "flype://dictate/other?request=\(request.id)", "flype://dictate?request=\(request.id)&extra=true",
        ] {
            XCTAssertNil(KeyboardStartRequest.requestID(from: URL(string: value)!))
        }
    }

    func testKeyboardLaunchUsesSchemeUniqueToCurrentApp() {
        let request = KeyboardStartRequest()
        XCTAssertEqual(request.url.scheme, "one.binda.flype")
        XCTAssertEqual(KeyboardStartRequest.requestID(from: request.url), request.id)
        XCTAssertEqual(
            KeyboardStartRequest.requestID(from: URL(string: "flype://dictate?request=\(request.id)")!), request.id)
        XCTAssertNil(
            KeyboardStartRequest.requestID(
                from: URL(string: "one.binda.flype://dictate?request=\(request.id)&extra=true")!))
        XCTAssertFalse(KeyboardStartRequest.acceptsAppURLScheme("de.flype"))
    }

    func testRequestMustMatchAndCanOnlyStartOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardStartStore(directory: directory)
        let request = KeyboardStartRequest()
        try store.issue(request)
        XCTAssertFalse(try store.consume(id: UUID()))
        XCTAssertTrue(try store.consume(id: request.id))
        XCTAssertFalse(try store.consume(id: request.id))
    }

    func testExpiredAndFutureRequestsCannotStartMicrophone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardStartStore(directory: directory)
        let now = Date()
        let request = KeyboardStartRequest(now: now)
        try store.issue(request)
        XCTAssertFalse(try store.consume(id: request.id, now: now.addingTimeInterval(30)))
        try store.issue(request)
        XCTAssertFalse(try store.consume(id: request.id, now: now.addingTimeInterval(-1)))
    }
    func testOneUseKeyboardRequestAuthorizesReturnInsertion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentID = UUID()
        let request = KeyboardStartRequest(targetDocumentID: documentID)
        let store = KeyboardStartStore(directory: directory)
        try store.issue(request)
        let consumed = try XCTUnwrap(store.consumeRequest(id: request.id))
        XCTAssertEqual(consumed.targetDocumentID, documentID)
        XCTAssertNil(try store.consumeRequest(id: request.id))
        let now = Date()
        let result = DictationResult(text: "Hallo Anna", now: now, keyboardRequestID: consumed.id)
        let decoded = try JSONDecoder().decode(DictationResult.self, from: JSONEncoder().encode(result))
        XCTAssertTrue(decoded.canAutoInsert(at: now))
        XCTAssertEqual(decoded.keyboardRequestID, request.id)
        XCTAssertFalse(decoded.canAutoInsert(at: now.addingTimeInterval(-1)))
        XCTAssertFalse(decoded.canAutoInsert(at: now.addingTimeInterval(120)))
        XCTAssertTrue(decoded.isValid(at: now.addingTimeInterval(120)))  // Manual recovery still works.
        XCTAssertFalse(DictationResult(text: "Manuell", now: now).canAutoInsert(at: now))
    }

    func testReturnDestinationTravelsOnlyWithConsumedRequest() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardStartStore(directory: directory)
        let request = KeyboardStartRequest(returnApplicationID: "com.apple.mobilenotes")
        try store.issue(request)
        XCTAssertNil(try store.consumeRequest(id: UUID()))
        XCTAssertEqual(try store.consumeRequest(id: request.id)?.returnApplicationID, "com.apple.mobilenotes")
        XCTAssertNil(try store.consumeRequest(id: request.id))
    }

    func testTappedLinkCanRepublishItsExactCapabilityAfterRefresh() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardStartStore(directory: directory)
        let document = UUID()
        let tapped = KeyboardStartRequest(targetDocumentID: document, returnApplicationID: "com.apple.mobilenotes")
        try store.issue(tapped)
        let refreshed = KeyboardStartRequest(targetDocumentID: UUID())
        try store.issue(refreshed)
        // The Link still contains the earlier ID. Re-publish that captured snapshot before opening it.
        try store.issue(tapped)
        XCTAssertNil(try store.consumeRequest(id: refreshed.id))
        let consumed = try XCTUnwrap(
            store.consumeRequest(id: XCTUnwrap(KeyboardStartRequest.requestID(from: tapped.url))))
        XCTAssertEqual(consumed, tapped)
        XCTAssertEqual(consumed.targetDocumentID, document)
        XCTAssertEqual(consumed.returnApplicationID, "com.apple.mobilenotes")
        XCTAssertNil(try store.consumeRequest(id: tapped.id))
    }

}
