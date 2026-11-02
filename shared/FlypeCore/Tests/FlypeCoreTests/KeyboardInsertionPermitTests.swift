import XCTest

@testable import FlypeCore

final class KeyboardInsertionPermitTests: XCTestCase {
    func testSameFieldAcceptsOnlyMatchingRecording() {
        let request = UUID()
        let document = UUID()
        let permit = KeyboardInsertionPermit(requestID: request, documentID: document, awaitingReturn: false)
        XCTAssertTrue(permit.allows(requestID: request, documentID: document))
        XCTAssertFalse(permit.allows(requestID: UUID(), documentID: document))
        XCTAssertFalse(permit.allows(requestID: request, documentID: nil))
    }
    func testFieldChangeCannotBeUndoneByReturning() {
        let request = UUID()
        let document = UUID()
        var permit = KeyboardInsertionPermit(requestID: request, documentID: document, awaitingReturn: false)
        permit.observe(documentID: UUID(), activeRequestID: request)
        permit.observe(documentID: document, activeRequestID: request)
        XCTAssertTrue(permit.invalidated)
        XCTAssertFalse(permit.allows(requestID: request, documentID: document))
    }
    func testInitialReturnCanRebindOnlyAfterMatchingSessionIsObserved() {
        let request = UUID()
        let returnedDocument = UUID()
        var permit = KeyboardInsertionPermit(requestID: request, documentID: UUID(), awaitingReturn: true)
        permit.observe(documentID: returnedDocument, activeRequestID: UUID(), now: 0)
        XCTAssertFalse(permit.allows(requestID: request, documentID: returnedDocument))
        permit.observe(documentID: returnedDocument, activeRequestID: request, now: 1)
        permit.observe(documentID: returnedDocument, activeRequestID: request, now: 1.4)
        XCTAssertTrue(permit.allows(requestID: request, documentID: returnedDocument))
        permit.observe(documentID: UUID(), activeRequestID: request)
        XCTAssertTrue(permit.invalidated)
    }

    func testFastCompletedResultCanBindAfterReturnWithoutBusySession() {
        let request = UUID()
        let document = UUID()
        var permit = KeyboardInsertionPermit(requestID: request, documentID: UUID(), awaitingReturn: true)
        permit.observe(documentID: document, activeRequestID: nil, completedRequestID: request, now: 1)
        XCTAssertFalse(permit.allows(requestID: request, documentID: document))
        permit.observe(documentID: document, activeRequestID: nil, completedRequestID: request, now: 1.4)
        XCTAssertTrue(permit.allows(requestID: request, documentID: document))
    }
    func testTransientReturnDocumentDoesNotInvalidatePermission() {
        let request = UUID()
        let document = UUID()
        var permit = KeyboardInsertionPermit(requestID: request, documentID: UUID(), awaitingReturn: true)
        permit.observe(documentID: UUID(), activeRequestID: request, now: 1)
        permit.observe(documentID: document, activeRequestID: request, now: 1.1)
        permit.observe(documentID: document, activeRequestID: request, now: 1.5)
        XCTAssertFalse(permit.invalidated)
        XCTAssertTrue(permit.allows(requestID: request, documentID: document))
    }
    func testPermissionSurvivesExtensionRecreationDuringReturn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardInsertionPermitStore(directory: directory)
        let request = UUID()
        let document = UUID()
        var permit = KeyboardInsertionPermit(requestID: request, documentID: UUID(), awaitingReturn: true)
        permit.observe(documentID: UUID(), activeRequestID: request, now: 1)
        try store.save(permit)
        var restored = try XCTUnwrap(KeyboardInsertionPermitStore(directory: directory).load())
        restored.observe(documentID: document, activeRequestID: nil, completedRequestID: request, now: 2)
        restored.observe(documentID: document, activeRequestID: nil, completedRequestID: request, now: 2.4)
        XCTAssertTrue(restored.allows(requestID: request, documentID: document))
        restored.observe(documentID: UUID(), activeRequestID: request)
        try store.save(restored)
        XCTAssertTrue(try XCTUnwrap(store.load()).invalidated)
    }
    func testExpiredOrFuturePermissionIsNotRestored() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardInsertionPermitStore(directory: directory)
        let now = Date()
        let request = UUID()
        let document = UUID()
        let permit = KeyboardInsertionPermit(
            requestID: request, documentID: document, awaitingReturn: false, createdAt: now)
        try store.save(permit)
        XCTAssertNil(try store.load(now: now.addingTimeInterval(600)))
        try store.save(permit)
        XCTAssertNil(try store.load(now: now.addingTimeInterval(-1)))
    }
    func testClearingOldResultDoesNotRemoveNewPermission() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KeyboardInsertionPermitStore(directory: directory)
        let request = UUID()
        let document = UUID()
        try store.save(KeyboardInsertionPermit(requestID: request, documentID: document, awaitingReturn: false))
        try store.clear(requestID: UUID())
        XCTAssertTrue(try XCTUnwrap(store.load()).allows(requestID: request, documentID: document))
        try store.clear(requestID: request)
        XCTAssertNil(try store.load())
    }
}
