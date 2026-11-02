import XCTest

@testable import FlypeCore

final class OnboardingProgressTests: XCTestCase {
    func testFirstLaunchAndPausedSetupAreDifferent() {
        var progress = OnboardingProgress()
        XCTAssertTrue(progress.shouldPresentAutomatically)
        progress.hasBeenPresented = true
        XCTAssertFalse(progress.shouldPresentAutomatically)
        XCTAssertFalse(progress.completed)
    }
    func testKeyboardMustBeAcknowledgedBeforeAdvancing() {
        var progress = OnboardingProgress()
        XCTAssertTrue(progress.advance())
        XCTAssertEqual(progress.step, .keyboard)
        XCTAssertFalse(progress.advance())
        XCTAssertFalse(progress.advance(skipOptional: true))
        progress.keyboardAcknowledged = true
        XCTAssertTrue(progress.advance())
        XCTAssertEqual(progress.step, .fullAccess)
    }
    func testFullAccessRequiresAcknowledgementUnlessTypingOnlyIsChosen() {
        var progress = OnboardingProgress()
        progress.step = .fullAccess
        XCTAssertFalse(progress.advance())
        XCTAssertTrue(progress.advance(skipOptional: true))
        XCTAssertEqual(progress.step, .practice)
        XCTAssertFalse(progress.fullAccessAcknowledged)
        XCTAssertFalse(progress.dictationTestSucceeded)
    }
    func testGrantedFullAccessContinuesToMicrophone() {
        var progress = OnboardingProgress()
        progress.step = .fullAccess
        progress.fullAccessAcknowledged = true
        XCTAssertTrue(progress.advance())
        XCTAssertEqual(progress.step, .microphone)
    }
    func testDeniedMicrophoneDoesNotTrapUserOrBecomeAClaimedGrant() {
        var progress = OnboardingProgress()
        progress.step = .microphone
        XCTAssertFalse(progress.advance(microphoneGranted: false))
        XCTAssertTrue(progress.advance(microphoneGranted: false, skipOptional: true))
        XCTAssertEqual(progress.step, .practice)
        XCTAssertFalse(progress.dictationTestSucceeded)
    }
    func testGrantedMicrophoneCanContinueNormally() {
        var progress = OnboardingProgress()
        progress.step = .microphone
        XCTAssertTrue(progress.advance(microphoneGranted: true))
        XCTAssertEqual(progress.step, .practice)
    }
    func testSkippingPracticeIsNotASuccessfulDictation() {
        var progress = OnboardingProgress()
        progress.step = .practice
        XCTAssertFalse(progress.advance())
        XCTAssertTrue(progress.advance(skipOptional: true))
        XCTAssertEqual(progress.step, .finish)
        XCTAssertFalse(progress.dictationTestSucceeded)
    }
    func testSuccessfulPracticeAdvancesAndCompletionNeedsFinalStep() {
        var progress = OnboardingProgress()
        XCTAssertFalse(progress.complete())
        progress.step = .practice
        progress.dictationTestSucceeded = true
        XCTAssertTrue(progress.advance())
        XCTAssertTrue(progress.complete())
        XCTAssertTrue(progress.completed)
        XCTAssertFalse(progress.shouldPresentAutomatically)
        XCTAssertFalse(progress.advance())
    }
    func testBackKeepsAcknowledgementsAndDoesNotGoBeforeWelcome() {
        var progress = OnboardingProgress()
        progress.keyboardAcknowledged = true
        progress.step = .fullAccess
        progress.goBack()
        XCTAssertEqual(progress.step, .keyboard)
        XCTAssertTrue(progress.keyboardAcknowledged)
        progress.goBack()
        progress.goBack()
        XCTAssertEqual(progress.step, .welcome)
    }
    func testPracticeSuccessNeedsPublishedTextToActuallyArrive() {
        func confirmed(_ before: String, _ after: String, _ published: Bool = true, _ current: Bool = true) -> Bool {
            OnboardingProgress.confirmsPracticeInsertion(
                before: before, after: after, dictation: "Hallo",
                published: published, sawCurrentPublication: current)
        }
        XCTAssertTrue(confirmed("", "Hallo "))
        XCTAssertTrue(confirmed("Vorher ", "Vorher Hallo "))
        XCTAssertFalse(confirmed("Hallo", "Hallo"))
        XCTAssertFalse(confirmed("Hallo", "Hallo!"))
        XCTAssertFalse(confirmed("", "Etwas anderes"))
        XCTAssertFalse(confirmed("", "Hallo ", false))
        XCTAssertFalse(confirmed("", "Hallo ", true, false))
    }
    func testPracticeHandlesExistingTextUnicodeAndTrimmedHandoffs() {
        XCTAssertTrue(
            OnboardingProgress.confirmsPracticeInsertion(
                before: "Hallo ", after: "Hallo Hallo ",
                dictation: "Hallo", published: true, sawCurrentPublication: true))
        XCTAssertTrue(
            OnboardingProgress.confirmsPracticeInsertion(
                before: "👋 ", after: "👋 Grüße 👋 ",
                dictation: " Grüße 👋\n", published: true, sawCurrentPublication: true))
        XCTAssertFalse(
            OnboardingProgress.confirmsPracticeInsertion(
                before: "", after: " ",
                dictation: " ", published: true, sawCurrentPublication: true))
    }
    func testProgressPersistsWithoutPracticeTextOrAudio() throws {
        let suite = "flype.onboarding.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var progress = OnboardingProgress()
        progress.hasBeenPresented = true
        progress.keyboardAcknowledged = true
        progress.step = .fullAccess
        progress.save(to: defaults)
        XCTAssertEqual(OnboardingProgress.load(from: defaults), progress)
        let data = defaults.data(forKey: "flype.onboarding.progress")!
        let keys = Set((try JSONSerialization.jsonObject(with: data) as! [String: Any]).keys)
        XCTAssertEqual(
            keys,
            [
                "schemaVersion", "step", "hasBeenPresented", "completed", "keyboardAcknowledged",
                "fullAccessAcknowledged", "dictationTestSucceeded",
            ])
    }
    func testCorruptAndFutureProgressSafelyRestartTheGuide() throws {
        let suite = "flype.onboarding.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "flype.onboarding.progress")
        XCTAssertEqual(OnboardingProgress.load(from: defaults), OnboardingProgress())
        var future = OnboardingProgress()
        future.schemaVersion = 99
        defaults.set(try JSONEncoder().encode(future), forKey: "flype.onboarding.progress")
        XCTAssertEqual(OnboardingProgress.load(from: defaults), OnboardingProgress())
    }
    func testKeyboardPresenceOnlyAcknowledgesThisPracticeSession() {
        let started = Date(timeIntervalSinceReferenceDate: 100)
        let now = started.addingTimeInterval(10)
        XCTAssertTrue(OnboardingProgress.keyboardWasSeen(started, since: started, now: now))
        XCTAssertTrue(OnboardingProgress.keyboardWasSeen(now, since: started, now: now))
        XCTAssertFalse(OnboardingProgress.keyboardWasSeen(started.addingTimeInterval(-1), since: started, now: now))
        XCTAssertFalse(OnboardingProgress.keyboardWasSeen(now.addingTimeInterval(1), since: started, now: now))
        XCTAssertFalse(
            OnboardingProgress.keyboardWasSeen(Date(timeIntervalSinceReferenceDate: .nan), since: started, now: now))
    }

}
