import Darwin
import Foundation
import XCTest

@testable import FlypeCore

final class VoiceSessionStoreTests: XCTestCase {
    private func withStore(_ action: (VoiceSessionStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try action(VoiceSessionStore(directory: directory))
    }
    func testDeadOrFutureHeartbeatCannotStartRecording() throws {
        try withStore { store in
            let now = Date()
            let id = UUID()
            try store.publish(.init(id: id, phase: .ready, dictationID: nil, now: now))
            XCTAssertNotNil(try store.state(now: now.addingTimeInterval(2.9)))
            XCTAssertNil(try store.state(now: now.addingTimeInterval(3)))
            XCTAssertNil(try store.state(now: now.addingTimeInterval(-1)))
            XCTAssertThrowsError(
                try store.send(
                    .init(sessionID: id, requestID: UUID(), action: .start, now: now), now: now.addingTimeInterval(3)))
        }
    }
    func testCommandsAreBoundToSessionAndConsumedOnce() throws {
        try withStore { store in
            let now = Date()
            let id = UUID()
            let request = UUID()
            try store.publish(.init(id: id, phase: .ready, dictationID: nil, now: now))
            XCTAssertThrowsError(
                try store.send(.init(sessionID: UUID(), requestID: request, action: .start, now: now), now: now))
            try store.send(.init(sessionID: id, requestID: request, action: .start, now: now), now: now)
            XCTAssertEqual(try store.claim(sessionID: id, now: now)?.requestID, request)
            XCTAssertNil(try store.claim(sessionID: id, now: now))
        }
    }
    func testExpiredCommandAndCommandsFromPreviousSessionAreDiscarded() throws {
        try withStore { store in
            let now = Date()
            let id = UUID()
            try store.publish(.init(id: id, phase: .recording, dictationID: UUID(), now: now))
            try store.send(.init(sessionID: id, requestID: UUID(), action: .stop, now: now), now: now)
            XCTAssertNil(try store.claim(sessionID: id, now: now.addingTimeInterval(5)))
            try store.send(.init(sessionID: id, requestID: UUID(), action: .start, now: now), now: now)
            XCTAssertNil(try store.claim(sessionID: UUID(), now: now))
            XCTAssertNil(try store.claim(sessionID: id, now: now))
        }
    }
    func testStatusPublishingDoesNotOverwriteCommandAndClearRevokesSession() throws {
        try withStore { store in
            let now = Date()
            let id = UUID()
            let request = UUID()
            try store.publish(.init(id: id, phase: .ready, dictationID: nil, now: now))
            try store.send(.init(sessionID: id, requestID: request, action: .start, now: now), now: now)
            try store.publish(.init(id: id, phase: .preparing, dictationID: request, now: now))
            try store.keyboardSeen(now: now)
            XCTAssertEqual(try store.claim(sessionID: id, now: now)?.requestID, request)
            XCTAssertEqual(try store.lastKeyboardSeen(), now)
            try store.clear()
            XCTAssertNil(try store.state(now: now))
            XCTAssertNil(try store.lastKeyboardSeen())
        }
    }
    func testIdleTimeoutNeverStopsActiveDictationOrForegroundSession() {
        let now = Date()
        XCTAssertFalse(
            VoiceSessionPolicy.shouldEnd(
                isBusy: false, appIsActive: false, lastInteraction: now, now: now.addingTimeInterval(299)))
        XCTAssertTrue(
            VoiceSessionPolicy.shouldEnd(
                isBusy: false, appIsActive: false, lastInteraction: now, now: now.addingTimeInterval(300)))
        XCTAssertFalse(
            VoiceSessionPolicy.shouldEnd(
                isBusy: true, appIsActive: false, lastInteraction: now, now: now.addingTimeInterval(600)))
        XCTAssertFalse(
            VoiceSessionPolicy.shouldEnd(
                isBusy: false, appIsActive: true, lastInteraction: now, now: now.addingTimeInterval(600)))
    }

    func testFreshnessClockIsReadUnderTheSameLockAsStatusAndCommands() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VoiceSessionStore(directory: directory)
        let now = Date()
        let id = UUID()
        try store.publish(.init(id: id, phase: .recording, dictationID: UUID(), now: now))
        let probe = open(directory.appendingPathComponent("session.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(probe, 0)
        guard probe >= 0 else { return }
        defer { close(probe) }
        var reads = 0
        func lockedClock() -> Date {
            reads += 1
            let acquired = flock(probe, LOCK_EX | LOCK_NB) == 0
            if acquired { _ = flock(probe, LOCK_UN) }
            XCTAssertFalse(
                acquired, "A concurrent heartbeat must not arrive between sampling the clock and reading state")
            return now
        }
        XCTAssertNotNil(try store.state(now: lockedClock()))
        let command = VoiceSessionCommand(sessionID: id, requestID: UUID(), action: .stop, now: now)
        try store.send(command, now: lockedClock())
        XCTAssertEqual(try store.claim(sessionID: id, now: lockedClock())?.requestID, command.requestID)
        XCTAssertEqual(reads, 3)
    }

    func testCancelReplacesAnUnprocessedStop() throws {
        try withStore { store in
            let id = UUID()
            let requestID = UUID()
            let now = Date()
            try store.publish(VoiceSessionState(id: id, phase: .recording, dictationID: requestID, now: now))
            try store.send(VoiceSessionCommand(sessionID: id, requestID: requestID, action: .stop, now: now), now: now)
            try store.send(
                VoiceSessionCommand(sessionID: id, requestID: requestID, action: .cancel, now: now), now: now)
            XCTAssertEqual(try store.claim(sessionID: id, now: now)?.action, .cancel)
        }
    }

    func testStopNeverReplacesAnUnprocessedCancel() throws {
        try withStore { store in
            let id = UUID()
            let requestID = UUID()
            let now = Date()
            try store.publish(VoiceSessionState(id: id, phase: .recording, dictationID: requestID, now: now))
            try store.send(
                VoiceSessionCommand(sessionID: id, requestID: requestID, action: .cancel, now: now), now: now)
            try store.send(VoiceSessionCommand(sessionID: id, requestID: requestID, action: .stop, now: now), now: now)
            XCTAssertEqual(try store.claim(sessionID: id, now: now)?.action, .cancel)
        }
    }

    @MainActor
    func testOnlyAWrittenCommandWakesTheApp() throws {
        var signals = 0
        let observation = SessionSignal.command.observe { signals += 1 }
        XCTAssertNotNil(observation)
        try withStore { store in
            let now = Date()
            let id = UUID()
            try store.publish(.init(id: id, phase: .ready, dictationID: nil, now: now))
            try store.send(.init(sessionID: id, requestID: UUID(), action: .start, now: now), now: now)
            // A second press while the first is unprocessed is dropped, so nothing new is signalled.
            try store.send(.init(sessionID: id, requestID: UUID(), action: .start, now: now), now: now)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(signals, 1)
        _ = observation
    }
    func testOnlyTextPhasesCountAsWorking() {
        XCTAssertTrue(VoiceSessionState.Phase.preparing.isWorking)
        XCTAssertTrue(VoiceSessionState.Phase.processing.isWorking)
        XCTAssertTrue(VoiceSessionState.Phase.cleaning.isWorking)
        XCTAssertFalse(VoiceSessionState.Phase.ready.isWorking)
        XCTAssertFalse(VoiceSessionState.Phase.recording.isWorking)
    }
}
