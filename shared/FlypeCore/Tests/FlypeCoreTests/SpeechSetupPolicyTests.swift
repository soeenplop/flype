import XCTest

@testable import FlypeCore

final class SpeechSetupPolicyTests: XCTestCase {
    func testInstalledParakeetNeverAsksAgain() {
        for provider in SpeechProvider.allCases {
            for apple in [true, false] {
                XCTAssertEqual(
                    SpeechSetupPolicy.requirement(provider: provider, parakeetInstalled: true, appleAvailable: apple),
                    .ready)
            }
        }
    }
    func testMissingParakeetOffersAChoiceWhenAppleRecognitionWorks() {
        XCTAssertEqual(
            SpeechSetupPolicy.requirement(provider: .parakeet, parakeetInstalled: false, appleAvailable: true), .choice)
    }
    func testChosenAppleRecognitionDoesNotAskAgain() {
        XCTAssertEqual(
            SpeechSetupPolicy.requirement(provider: .apple, parakeetInstalled: false, appleAvailable: true), .ready)
    }
    func testDownloadIsMandatoryWithoutAppleRecognition() {
        for provider in SpeechProvider.allCases {
            XCTAssertEqual(
                SpeechSetupPolicy.requirement(provider: provider, parakeetInstalled: false, appleAvailable: false),
                .downloadRequired)
        }
    }
    func testPersistedDownloadResumesOnceEvenIfEveryRefreshStillFindsTheMarker() {
        var policy = DownloadResumePolicy()
        XCTAssertFalse(policy.consume(pending: false))
        XCTAssertTrue(policy.consume(pending: true))
        for _ in 0..<10 { XCTAssertFalse(policy.consume(pending: true)) }
        var manual = DownloadResumePolicy()
        manual.beganDownload()
        XCTAssertFalse(manual.consume(pending: true))
        // A new launch may try once again; a failed attempt cannot recurse in the same controller.
        var relaunched = DownloadResumePolicy()
        XCTAssertTrue(relaunched.consume(pending: true))
    }

}
