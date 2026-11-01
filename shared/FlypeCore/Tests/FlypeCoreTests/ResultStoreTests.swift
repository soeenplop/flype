import Foundation
import XCTest

@testable import FlypeCore

final class ResultStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ResultStore!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = ResultStore(directory: directory)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testResultSurvivesNewStoreAndCanOnlyBeClaimedOnce() throws {
        let result = DictationResult(text: "Grüße aus Köln: 12,50 €.", now: now)
        try store.publish(result, now: now)
        let keyboardStore = ResultStore(directory: directory)
        XCTAssertEqual(try keyboardStore.pending(now: now), result)
        XCTAssertEqual(try keyboardStore.claim(id: result.id, now: now), result)
        XCTAssertNil(try store.claim(id: result.id, now: now))
        XCTAssertNil(try store.pending(now: now))
    }

    func testExpiredResultCannotBeInserted() throws {
        let result = DictationResult(text: "Vertraulich", now: now, lifetime: 60)
        try store.publish(result, now: now)
        XCTAssertNil(try store.claim(id: result.id, now: now.addingTimeInterval(60)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
    }

    func testOldPreviewCannotClaimNewerResult() throws {
        let first = DictationResult(text: "Erste Transkription", now: now)
        let second = DictationResult(text: "Zweites Transkription", now: now)
        try store.publish(first, now: now)
        try store.publish(second, now: now)
        XCTAssertNil(try store.claim(id: first.id, now: now))
        XCTAssertEqual(try store.pending(now: now), second)
    }

    func testEmptyAndExpiredResultsAreRejected() {
        XCTAssertThrowsError(try store.publish(DictationResult(text: " \n ", now: now), now: now))
        XCTAssertThrowsError(try store.publish(DictationResult(text: "Alt", now: now, lifetime: -1), now: now))
    }

    func testConcurrentClaimsHaveOneWinner() throws {
        let result = DictationResult(text: "Einmal", now: now)
        try store.publish(result, now: now)
        let counter = LockedCounter()
        let directory = directory!
        let timestamp = now
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do {
                if try ResultStore(directory: directory).claim(id: result.id, now: timestamp) != nil {
                    counter.increment()
                }
            } catch { counter.recordFailure() }
        }
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(counter.failures, 0)
    }

    func testClearRemovesSensitivePayload() throws {
        try store.publish(DictationResult(text: "Privat", now: now), now: now)
        try store.clear()
        XCTAssertNil(try store.pending(now: now))
    }

    func testCorruptedStoreDoesNotOfferText() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("pending.json"))
        XCTAssertThrowsError(try store.pending(now: now))
    }

    func testHandoffWithProductionClockDefaults() throws {
        try store.publish(DictationResult(text: "Bereit für die Tastatur."))
        let keyboard = ResultStore(directory: directory)
        let result = try XCTUnwrap(keyboard.pending())
        XCTAssertEqual(result.text, "Bereit für die Tastatur.")
        XCTAssertNotNil(try keyboard.claim(id: result.id))
    }

    func testMissingResultIsNotReportedAsReadFailure() throws {
        XCTAssertNil(try store.pending(now: now))
        XCTAssertNoThrow(try store.clear())
    }

    func testValidityRejectsFutureAndExactExpiryButAcceptsCreation() {
        let result = DictationResult(text: "Grenzfall", now: now, lifetime: 60)
        XCTAssertFalse(result.isValid(at: now.addingTimeInterval(-0.001)))
        XCTAssertTrue(result.isValid(at: now))
        XCTAssertTrue(result.isValid(at: now.addingTimeInterval(59.999)))
        XCTAssertFalse(result.isValid(at: now.addingTimeInterval(60)))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var errors = 0
    var count: Int { lock.withLock { value } }
    var failures: Int { lock.withLock { errors } }
    func increment() { lock.withLock { value += 1 } }
    func recordFailure() { lock.withLock { errors += 1 } }
}
