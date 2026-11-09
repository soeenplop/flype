import AVFoundation
import Combine
import FlypeCore
import Speech
import SwiftUI

@MainActor
final class DictationController: NSObject, ObservableObject {
    enum Phase { case idle, preparing, recording, transcribing, cleaning, finished, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "Alles bereit"
    @Published private(set) var elapsed = 0
    @Published private(set) var transcript = ""
    @Published private(set) var published = false
    @Published private(set) var notice: String?
    @Published private(set) var inputLevel: Double = 0
    @Published private(set) var sessionActive = false
    private var sessionID = UUID()
    private var sessionTask: Task<Void, Never>?
    private var commandObservation: SessionSignalObservation?
    private var signaledState: (phase: VoiceSessionState.Phase, dictationID: UUID)?
    private var lastInteraction = Date()
    private var recorder: MicrophoneCapture?
    private var audioURL: URL?
    private var ticker: Task<Void, Never>?
    private var work: Task<Void, Never>?
    private var preparation: Task<Void, Error>?
    private var rawTranscript = ""
    private var usesStandardRecognition = false
    @Published private(set) var cleanupNotice: String?
    @Published private(set) var activeMode = DictationMode.cleaned
    private var engine: (any SpeechRecognitionEngine)?
    private var options = DictationOptions.current()
    private var dictionary = DictionarySnapshot()
    private let cleanup = TextCleanupService()
    private let dictionaryCorrection = DictionaryCorrectionService()
    private var dictionaryTask: Task<DictionaryCorrectionResult, Error>?
    private var cleanupTask: Task<String, Error>?
    private var failureStage = "Vorbereitung"
    private var watchdog: Task<Void, Never>?
    private var operationID = UUID()
    /// The writing app is elsewhere, so the app shows how to get back to it.
    @Published private(set) var startedFromKeyboard = false
    private var keyboardRequestID: UUID?
    private var timing: DictationTiming?

    var busy: Bool { phase == .preparing || phase == .recording || phase == .transcribing || phase == .cleaning }

    func start(fromKeyboard: Bool = false, keyboardRequestID: UUID? = nil) {
        guard !busy else { return }
        startedFromKeyboard = fromKeyboard
        self.keyboardRequestID = fromKeyboard ? keyboardRequestID : nil
        transcript = ""
        rawTranscript = ""
        cleanupNotice = nil
        options = .current()
        activeMode = options.mode
        usesStandardRecognition = false
        notice = nil
        published = false
        elapsed = 0
        inputLevel = 0
        phase = .preparing
        publishSession()
        operationID = UUID()
        let operation = operationID
        failureStage = "Mikrofonberechtigung"
        status = "Flype wird vorbereitet"
        work = Task { [self] in
            do {
                guard await AVAudioApplication.requestRecordPermission() else {
                    throw DictationError.microphoneDenied
                }
                try Task.checkCancellation()
                guard operationID == operation else { return }
                // A synced choice can reach a device without the model. Dictation then uses Apple recognition
                // where it exists; the setup screen covers the devices where it does not.
                let parakeetReady = await ParakeetModelStore.shared.isInstalled()
                let useParakeet: Bool
                if parakeetReady && options.provider == .parakeet {
                    useParakeet = true
                } else if await AppleSpeechEngine.isAvailable(language: options.language) {
                    useParakeet = false
                } else if parakeetReady {
                    useParakeet = true
                } else {
                    throw ParakeetModelStore.Failure.missing
                }
                try Task.checkCancellation()
                guard operationID == operation else { return }
                usesStandardRecognition = options.provider == .parakeet && !useParakeet
                let engine: any SpeechRecognitionEngine =
                    useParakeet ? ParakeetSpeechEngine() : AppleSpeechEngine(language: options.language)
                self.engine = engine
                // Start capturing before dictionary/model preparation can delay the first words.
                try beginRecording()
                AccountController.prepareCleanup(mode: options.mode)
                let options = self.options
                let preparation = Task { [self] in
                    try Task.checkCancellation()
                    guard operationID == operation else { throw CancellationError() }
                    let snapshot = try PersonalDictionaryStore.shared().snapshot()
                    dictionary = snapshot
                    try await engine.prepare()
                    try Task.checkCancellation()
                    guard operationID == operation else { throw CancellationError() }
                    if snapshot.entries.contains(where: { $0.enabled && $0.useForDictation }) {
                        await dictionaryCorrection.prepare(language: options.language)
                    }
                    try Task.checkCancellation()
                }
                self.preparation = preparation
                armWatchdog(seconds: 180, operation: operation, error: .preparationTimedOut)
                try await preparation.value
                guard !Task.isCancelled, operationID == operation else { return }
                if phase == .recording { watchdog?.cancel() }
            } catch is CancellationError {
                // The explicit cancel action already restored the UI.
            } catch {
                if !Task.isCancelled && operationID == operation { fail(error) }
            }
        }
    }

    private func beginRecording() throws {
        failureStage = "Mikrofon vorbereiten"
        failureStage = "Aufnahme starten"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlypeAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        audioURL = url
        let recorder = self.recorder ?? MicrophoneCapture()
        self.recorder = recorder
        try recorder.start(url: url)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        phase = .recording
        activateSession()
        #if DEBUG
            print(
                "FLYPE_RECORDING_STARTED engine=AVAudioEngine background=\(UIApplication.shared.applicationState != .active)"
            )
        #endif
        status = "Ich höre zu …"
        #if DEBUG
            if startedFromKeyboard, let keyboardRequestID {
                _ = PreviousAppReturn.shared.attempt(for: keyboardRequestID)
            }
        #endif
        ticker = Task { [weak self] in
            let started = ContinuousClock.now
            #if DEBUG
                var reportedMeter = false
            #endif
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self, self.phase == .recording else { return }
                #if DEBUG
                    if !reportedMeter, let frames = self.recorder?.meterFrameCount, frames > 0 {
                        print("FLYPE_FAST_METER frames=\(frames)")
                        reportedMeter = true
                    }
                #endif
                self.elapsed = Int(self.recorder?.duration ?? 0)
                self.inputLevel = MicrophoneLevel.normalized(rms: Double(self.recorder?.level ?? 0))
                if let error = self.recorder?.error {
                    self.fail(error)
                    return
                }
                if started.duration(to: .now) > .seconds(4), self.elapsed == 0 {
                    self.fail(DictationError.emptyRecording)
                    return
                }
                if self.elapsed >= 120 {
                    self.finish()
                    return
                }
            }
        }
    }

    func finish() {
        guard phase == .recording else { return }
        phase = .transcribing
        status = "Dein Text entsteht …"
        failureStage = "Sprache erkennen"
        let operation = operationID
        elapsed = Int(recorder?.duration ?? Double(elapsed))
        if sessionActive { recorder?.finishSegment() } else { recorder?.stop() }
        publishSession()
        #if DEBUG
            if let recorder {
                print(
                    "FLYPE_MICROPHONE_SIGNAL duration=\(recorder.duration) peak=\(recorder.peak) muted=\(AVAudioApplication.shared.isInputMuted)"
                )
            }
        #endif
        ticker?.cancel()
        if !sessionActive { deactivateAudio() }
        timing = DictationTiming()
        guard let audioURL, let engine else {
            fail(DictationError.recordingFailed)
            return
        }
        // A very short dictation can finish while the recognizer is still loading.
        let preparation = self.preparation
        armWatchdog(seconds: preparation == nil ? 30 : 180, operation: operation, error: .processingTimedOut)
        work = Task { [self] in
            guard operationID == operation, !Task.isCancelled else { return }
            do {
                try await preparation?.value
                try Task.checkCancellation()
                guard operationID == operation else { return }
                self.preparation = nil
                // Model and dictionary loading that was still running when the recording ended.
                timing?.mark("preparation")
                armWatchdog(seconds: 30, operation: operation, error: .processingTimedOut)
                let file = try AVAudioFile(forReading: audioURL)
                guard file.length > 0 else { throw DictationError.emptyRecording }
                let text = try await engine.transcribe(file: audioURL).trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard operationID == operation else { return }
                guard !text.isEmpty else { throw DictationError.noSpeech }
                timing?.mark("recognition")
                rawTranscript = text
                var wordText = dictionary.applyingAliases(to: text)
                var dictionaryNotice: String?
                var soundAlikes: [DictionarySoundAlike] = []
                self.engine = nil
                watchdog?.cancel()
                if dictionary.entries.contains(where: { $0.enabled && $0.useForDictation }) {
                    status = "Dein Text entsteht …"
                    failureStage = "Wörterbuch prüfen"
                    let originalWordText = wordText
                    let snapshot = dictionary
                    let service = dictionaryCorrection
                    let task = Task {
                        try await service.correct(originalWordText, file: audioURL, dictionary: snapshot)
                    }
                    dictionaryTask = task
                    watchdog = Task { [weak self] in
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        guard let self, self.operationID == operation, self.phase == .transcribing else { return }
                        task.cancel()
                        self.finishResult(
                            originalWordText, operation: operation,
                            notice:
                                "Die Wörterbuchprüfung dauert zu lange. Dein erkannter Text wurde unverändert übernommen."
                        )
                    }
                    let correction = try await task.value
                    try Task.checkCancellation()
                    guard operationID == operation, phase == .transcribing else { return }
                    watchdog?.cancel()
                    dictionaryTask = nil
                    wordText = correction.text
                    dictionaryNotice = correction.notice
                    soundAlikes = correction.soundAlikes
                    timing?.mark("dictionary")
                    #if DEBUG
                        print(
                            "FLYPE_DICTIONARY_RESULT changes=\(correction.changes) fallback=\(correction.notice != nil)"
                        )
                    #endif
                }
                let fieldContext = keyboardRequestID.flatMap { id in
                    (try? DictationFieldContextStore.shared())?.take(requestID: id)
                }
                removeAudio()
                if !AccountController.cleanupActive(mode: options.mode) {
                    finishResult(wordText, operation: operation, notice: dictionaryNotice)
                    return
                }
                phase = .cleaning
                status = "Dein Text entsteht …"
                publishSession()
                let snapshot = dictionary
                let service = cleanup
                let language = options.language
                let hints = soundAlikes
                let task = Task {
                    guard let token = try await AccountController.cloudCleanupToken() else {
                        throw SupabaseAPI.Failure.unauthorized
                    }
                    return try await service.clean(
                        wordText, dictionary: snapshot, language: language, cloudToken: token,
                        fieldContext: fieldContext?.text, followingText: fieldContext?.following, soundAlikes: hints)
                }
                cleanupTask = task
                watchdog = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    guard let self, self.operationID == operation, self.phase == .cleaning else { return }
                    task.cancel()
                    self.finishResult(
                        wordText, operation: operation,
                        notice:
                            "Die Bereinigung dauert zu lange. Dein erkannter Originaltext ist bereit."
                    )
                }
                do {
                    let result = try await task.value
                    try Task.checkCancellation()
                    guard operationID == operation, phase == .cleaning else { return }
                    finishResult(result, operation: operation, notice: dictionaryNotice)
                } catch {
                    guard operationID == operation, phase == .cleaning, !Task.isCancelled else { return }
                    finishResult(
                        wordText, operation: operation,
                        notice: (error as? SupabaseAPI.Failure).flatMap { $0.isLimit ? $0.errorDescription : nil }
                            ?? "Die Bereinigung ist gerade nicht verfügbar. Dein Originaltext ist bereit."
                    )
                }
            } catch {
                if !Task.isCancelled && operationID == operation && (phase == .transcribing || phase == .cleaning) {
                    fail(error)
                }
            }
        }
    }

    private func finishResult(_ text: String, operation: UUID, notice: String? = nil) {
        guard operationID == operation else { return }
        watchdog?.cancel()
        // The last step is the cleanup, or the dictionary check when it ran into its time limit.
        timing?.report(phase == .cleaning ? "cleanup" : "rest", characters: text.count)
        timing = nil
        cleanupTask = nil
        dictionaryTask = nil
        transcript = text
        cleanupNotice =
            notice
            ?? (usesStandardRecognition
                ? "Parakeet fehlt auf diesem Gerät. Flype hat die Apple-Spracherkennung verwendet." : nil)
        phase = .finished
        status = "Dein Text ist bereit."
        if !sessionActive { recorder = nil }
        lastInteraction = Date()
        publishSession()
        removeAudio()
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--dictionary-fixture") {
                print(
                    "FLYPE_DICTIONARY_PIPELINE expected=\(transcript.contains("Flype")) changed=\(transcript != rawTranscript)"
                )
            }
            print(
                "FLYPE_TRANSCRIPTION_OK characters=\(transcript.count) provider=\(options.provider.rawValue) mode=\(options.mode.rawValue)"
            )
        #endif
        if startedFromKeyboard { prepareHandoff() }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--diagnose-speech") {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        #endif
    }

    func prepareHandoff() {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let store = try ResultStore.shared()
            let result = DictationResult(text: transcript, keyboardRequestID: keyboardRequestID)
            try store.publish(result)
            SessionSignal.state.post()
            #if DEBUG
                print(
                    "FLYPE_HANDOFF_PUBLISHED directory=\(store.diagnosticDirectory.path) readable=\(try store.pending()?.id == result.id)"
                )
            #endif
            published = true
            notice =
                keyboardRequestID != nil
                ? "Fertig. Die Flype-Tastatur fügt den Text im aktiven Feld ein. Das Mikrofon bleibt für weitere Transkriptionen bereit."
                : "Bereit für 10 Minuten. Wechsle zurück, wähle die Flype-Tastatur und tippe auf Einfügen."
        } catch {
            published = false
            #if DEBUG
                let error = error as NSError
                print("FLYPE_HANDOFF_ERROR domain=\(error.domain) code=\(error.code)")
            #endif
            notice = error.localizedDescription
        }
    }

    /// Removes the text from the keyboard handoff and from this process; there is no history.
    func clearLastDictation() {
        do {
            try ResultStore.shared().clear()
            transcript = ""
            rawTranscript = ""
            cleanupNotice = nil
            notice = nil
            published = false
            if phase == .finished { phase = .idle }
        } catch { notice = error.localizedDescription }
    }

    func cancel() {
        stopWork()
        phase = .idle
        status = "Abgebrochen. Die Aufnahme wurde gelöscht."
    }

    /// Discards only this transcription. The microphone stays ready, so the next one needs no app switch.
    func discardCurrent() {
        guard sessionActive else {
            cancel()
            return
        }
        operationID = UUID()
        watchdog?.cancel()
        watchdog = nil
        work?.cancel()
        work = nil
        preparation?.cancel()
        preparation = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        dictionaryTask?.cancel()
        dictionaryTask = nil
        ticker?.cancel()
        recorder?.finishSegment()
        let activeEngine = engine
        engine = nil
        if let activeEngine { Task { await activeEngine.cancel() } }
        removeAudio()
        // The result may have been published just before the keyboard's command arrived.
        if published { try? ResultStore.shared().clear() }
        transcript = ""
        rawTranscript = ""
        cleanupNotice = nil
        notice = nil
        published = false
        startedFromKeyboard = false
        keyboardRequestID = nil
        elapsed = 0
        inputLevel = 0
        phase = .idle
        status = "Abgebrochen. Die Aufnahme wurde gelöscht."
        publishSession()
    }

    func endSession() {
        stopWork()
        Task { try? await ParakeetSpeechEngine.unload() }
        phase = .idle
        status = "Bereitschaft beendet. Das Mikrofon ist aus."
    }

    private func stopWork() {
        #if DEBUG
            if sessionActive { print("FLYPE_SESSION_ENDED") }
        #endif
        sessionActive = false
        sessionTask?.cancel()
        sessionTask = nil
        commandObservation = nil
        signaledState = nil
        try? VoiceSessionStore.shared().clear()
        operationID = UUID()
        watchdog?.cancel()
        watchdog = nil
        work?.cancel()
        work = nil
        preparation?.cancel()
        preparation = nil
        cleanupTask?.cancel()
        cleanupTask = nil
        dictionaryTask?.cancel()
        dictionaryTask = nil
        ticker?.cancel()
        recorder?.stop()
        recorder = nil
        let activeEngine = engine
        engine = nil
        if let activeEngine { Task { await activeEngine.cancel() } }
        deactivateAudio()
        removeAudio()
    }

    func handleBackground() {
        if busy && !sessionActive {
            cancel()
            status = "Aufnahme unterbrochen. Bleib für die Aufnahme in Flype."
        }
    }

    func interruptAudio() {
        guard sessionActive || busy else { return }
        let lostDictation = busy
        cancel()
        if lostDictation { markLost("Die Transkription wurde unterbrochen. Bitte starte sie erneut.") }
    }

    func handleProtectedDataLoss() {
        let lostDictation = busy
        endSession()
        if lostDictation { markLost("Die Bildschirmsperre hat die Transkription beendet. Bitte starte sie erneut.") }
    }

    private func markLost(_ message: String) {
        phase = .failed
        status = message
    }

    private func activateSession() {
        lastInteraction = Date()
        if sessionActive {
            publishSession()
            return
        }
        sessionID = UUID()
        sessionActive = true
        #if DEBUG
            print("FLYPE_SESSION_READY")
        #endif
        try? VoiceSessionStore.shared().clear()
        publishSession()
        sessionTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.phase == .recording ? 33 : 250
                try? await Task.sleep(for: .milliseconds(interval))
                guard !Task.isCancelled, let self, self.checkSession() else { return }
            }
        }
        // The keyboard signals each command, so it does not wait for the next poll.
        commandObservation = SessionSignal.command.observe { [weak self] in _ = self?.checkSession() }
    }

    /// Handles a pending keyboard command and refreshes the shared state. False once the session has ended.
    private func checkSession() -> Bool {
        guard sessionActive else { return false }
        do {
            guard recorder?.isRunning == true else {
                interruptAudio()
                return false
            }
            let store = try VoiceSessionStore.shared()
            if let command = try store.claim(sessionID: sessionID) {
                #if DEBUG
                    print("FLYPE_SESSION_COMMAND action=\(command.action.rawValue)")
                #endif
                lastInteraction = Date()
                switch command.action {
                case .start:
                    if !busy,
                        let request = try KeyboardStartStore.shared().consumeRequest(id: command.requestID)
                    {
                        start(fromKeyboard: true, keyboardRequestID: request.id)
                    }
                case .stop:
                    if phase == .recording,
                        command.requestID == (keyboardRequestID ?? operationID)
                    {
                        startedFromKeyboard = true
                        keyboardRequestID = command.requestID
                        finish()
                    }
                case .cancel:
                    if command.requestID == (keyboardRequestID ?? operationID) {
                        discardCurrent()
                    }
                case .end:
                    endSession()
                    return false
                }
            }
            if let seen = try store.lastKeyboardSeen(), Date().timeIntervalSince(seen) >= 0,
                Date().timeIntervalSince(seen) < 3
            {
                lastInteraction = Date()
            }
            if VoiceSessionPolicy.shouldEnd(
                isBusy: busy,
                appIsActive: UIApplication.shared.applicationState == .active,
                lastInteraction: lastInteraction)
            {
                endSession()
                return false
            }
            publishSession()
            return true
        } catch {
            // A locked/unavailable shared container must not leave an invisible live session.
            handleProtectedDataLoss()
            return false
        }
    }

    private func publishSession() {
        guard sessionActive else { return }
        let state: VoiceSessionState.Phase
        switch phase {
        case .preparing: state = .preparing
        case .recording: state = .recording
        case .transcribing: state = .processing
        case .cleaning: state = .cleaning
        default: state = .ready
        }
        let dictationID = keyboardRequestID ?? operationID
        try? VoiceSessionStore.shared().publish(
            VoiceSessionState(
                id: sessionID, phase: state, dictationID: dictationID,
                inputLevel: phase == .recording ? MicrophoneLevel.normalized(rms: Double(recorder?.level ?? 0)) : nil,
                recordingDuration: phase == .recording ? recorder?.duration : nil))
        // Only changes wake the keyboard. Levels during recording reach it through its own timer.
        if signaledState?.phase != state || signaledState?.dictationID != dictationID {
            signaledState = (state, dictationID)
            SessionSignal.state.post()
        }
    }

    private func fail(_ error: Error) {
        let systemError = error as NSError
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--diagnose-speech") {
                UIApplication.shared.isIdleTimerDisabled = false
            }
            // Never log audio, transcript text, userInfo, or file paths.
            print("FLYPE_ERROR stage=\(failureStage) domain=\(systemError.domain) code=\(systemError.code)")
        #endif
        stopWork()
        phase = .failed
        #if DEBUG
            print("FLYPE_RECOVERY_READY busy=\(busy)")
        #endif
        // The recognizer reports missing or unusable language assets in this domain.
        status =
            systemError.domain == "SFSpeechErrorDomain"
            ? "Die lokale Spracherkennung ist auf diesem Gerät gerade nicht verfügbar."
            : (error as? LocalizedError)?.errorDescription
                ?? "Die Transkription ist fehlgeschlagen. Bitte versuche es erneut."
    }

    private func armWatchdog(seconds: Double, operation: UUID, error: DictationError) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.operationID == operation, self.busy else { return }
            self.fail(error)
        }
    }

    private func removeAudio() {
        if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        audioURL = nil
        // A discarded dictation never read the field text, so it must not stay behind either.
        (try? DictationFieldContextStore.shared())?.clear()
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Remove recordings left by an unexpected process termination; no history is kept.
    static func clearAbandonedAudio() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FlypeAudio", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    #if DEBUG
        /// Explicit developer launch argument; no microphone capture and no user audio.
        /// The fixture is copied into this app's Documents directory by the device tools.
        func runDiagnosticsIfRequested() {
            if ProcessInfo.processInfo.arguments.contains("--verify-handoff") {
                transcript = "Dies ist ein Test der Flype-Tastaturübergabe."
                phase = .finished
                prepareHandoff()
                print("FLYPE_HANDOFF_SELF_TEST published=\(published)")
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--diagnose-handoff") {
                do {
                    let store = try ResultStore.shared()
                    print(
                        "FLYPE_HANDOFF_STATE directory=\(store.diagnosticDirectory.path) pending=\(try store.pending() != nil)"
                    )
                } catch {
                    let error = error as NSError
                    print("FLYPE_HANDOFF_STATE_ERROR domain=\(error.domain) code=\(error.code)")
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--diagnose-timeout") {
                phase = .transcribing
                let operation = operationID
                armWatchdog(seconds: 1, operation: operation, error: .processingTimedOut)
                return
            }
            guard ProcessInfo.processInfo.arguments.contains("--diagnose-speech") else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.record, mode: .spokenAudio)
                print("FLYPE_ORIGINAL_SESSION accepted")
            } catch {
                let error = error as NSError
                print("FLYPE_ORIGINAL_SESSION_ERROR domain=\(error.domain) code=\(error.code)")
            }
            do {
                try session.setCategory(.record, mode: .measurement)
                print("FLYPE_FIXED_SESSION_OK")
            } catch {
                let error = error as NSError
                print("FLYPE_FIXED_SESSION_ERROR domain=\(error.domain) code=\(error.code)")
            }
            let dictionaryFixture = ProcessInfo.processInfo.arguments.contains("--dictionary-fixture")
            let fixture = URL.documentsDirectory.appendingPathComponent(
                dictionaryFixture ? "flype-dictionary-test.wav" : "flype-speech-test.wav")
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                print("FLYPE_FIXTURE_MISSING")
                return
            }
            phase = .preparing
            status = "Lokale Testtranskription wird geprüft …"
            failureStage = "Sprachmodell prüfen"
            work = Task { [self] in
                do {
                    options = .current()
                    if ProcessInfo.processInfo.arguments.contains("--parakeet") { options.provider = .parakeet }
                    if ProcessInfo.processInfo.arguments.contains("--cleaned") { options.mode = .cleaned }
                    activeMode = options.mode
                    dictionary =
                        dictionaryFixture
                        ? DictionarySnapshot(entries: [.init(spelling: "Flype")])
                        : try PersonalDictionaryStore.shared().snapshot()
                    if dictionaryFixture { options.mode = .verbatim }
                    let selected: any SpeechRecognitionEngine =
                        options.provider == .parakeet ? ParakeetSpeechEngine() : AppleSpeechEngine()
                    engine = selected
                    let preparationStarted = ProcessInfo.processInfo.systemUptime
                    print("FLYPE_ENGINE_PREPARE_BEGIN provider=\(options.provider.rawValue)")
                    try await selected.prepare()
                    if dictionary.entries.contains(where: { $0.enabled && $0.useForDictation }) {
                        await dictionaryCorrection.prepare(language: options.language)
                    }
                    print("FLYPE_ENGINE_PREPARED seconds=\(ProcessInfo.processInfo.systemUptime - preparationStarted)")
                    // Copy to the normal temporary path, so finish() exercises normal cleanup.
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
                        UUID().uuidString + ".wav")
                    try FileManager.default.copyItem(at: fixture, to: temporary)
                    audioURL = temporary
                    phase = .recording
                    finish()
                } catch { if !Task.isCancelled { fail(error) } }
            }
        }
    #endif
}

private enum DictationError: LocalizedError {
    case microphoneDenied, languageUnavailable, recordingFailed, noSpeech
    case emptyRecording, processingTimedOut, preparationTimedOut
    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Bitte erlaube Flype den Mikrofonzugriff in den Systemeinstellungen."
        case .languageUnavailable: "Das ausgewählte Sprachmodell ist auf diesem Gerät nicht verfügbar."
        case .recordingFailed:
            "Die Aufnahme konnte nicht gestartet oder beendet werden. Prüfe, ob eine andere App das Mikrofon verwendet."
        case .noSpeech:
            "Keine Sprache erkannt. Sprich näher am Mikrofon und versuche es noch einmal."
        case .emptyRecording:
            "Das Mikrofon hat keine Audiodaten geliefert. Bitte starte eine neue Aufnahme und sprich einige Sekunden."
        case .processingTimedOut:
            "Die Spracherkennung hat nicht rechtzeitig geantwortet. Bitte starte eine neue Aufnahme."
        case .preparationTimedOut:
            "Die Vorbereitung dauert zu lange. Prüfe deine Verbindung für den Modelldownload und versuche es erneut."
        }
    }
}
