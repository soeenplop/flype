import Foundation
import XCTest

@testable import FlypeCore

final class MicrophoneLevelTests: XCTestCase {
    func testSilenceAndInvalidSamplesCannotAnimateTheMeter() {
        for rms in [0.0, -1, Double.nan, Double.infinity, -Double.infinity, 0.00001] {
            XCTAssertEqual(MicrophoneLevel.normalized(rms: rms), 0)
        }
    }
    func testQuietSpeechIsVisibleAndLoudSamplesAreBounded() {
        let quiet = MicrophoneLevel.normalized(rms: 0.01)
        let normal = MicrophoneLevel.normalized(rms: 0.05)
        XCTAssertGreaterThan(quiet, 0.2)
        XCTAssertGreaterThan(normal, quiet)
        XCTAssertLessThan(normal, 1)
        XCTAssertEqual(MicrophoneLevel.normalized(rms: 1), 1)
        XCTAssertEqual(MicrophoneLevel.normalized(rms: 10), 1)
    }
    func testLiveLevelMetadataRoundTripAndLegacyState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VoiceSessionStore(directory: directory)
        let now = Date()
        let id = UUID()
        try store.publish(
            .init(id: id, phase: .recording, dictationID: UUID(), now: now, inputLevel: 0.72, recordingDuration: 5.25))
        let restored = try XCTUnwrap(store.state(now: now))
        XCTAssertEqual(restored.inputLevel, 0.72)
        XCTAssertEqual(restored.recordingDuration, 5.25)
        let legacy = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString, "phase": "ready", "updatedAt": now.timeIntervalSinceReferenceDate,
        ])
        let decoded = try JSONDecoder().decode(VoiceSessionState.self, from: legacy)
        XCTAssertNil(decoded.inputLevel)
        XCTAssertNil(decoded.recordingDuration)
    }
}
