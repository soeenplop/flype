import AVFoundation
import AppKit
import ApplicationServices
import Combine
import FlypeCore
import SwiftUI

@MainActor
final class MacDictation: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var busy = false
    /// False from the moment text can reach another app, because that cannot be taken back.
    @Published private(set) var canCancel = false
    @Published private(set) var level: Float = 0
    @Published private(set) var status = "Alles bereit"
    @Published var result = ""
    @Published private(set) var original = ""
    @Published private(set) var cleanupNotice: String?
    @Published private(set) var shortcutReady = false
    @Published private(set) var microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published private(set) var accessibilityReady = AXIsProcessTrusted()
    private let shortcut = GlobalShortcut()
    private var capture: MicrophoneCapture?
    private var engine: (any SpeechRecognitionEngine)?
    private var preparation: Task<Void, Error>?
    private var dictionaryCorrection = DictionaryCorrectionService()
    private var options = DictationOptions(provider: .parakeet, mode: .cleaned)
    private var dictionary = DictionarySnapshot()
    private var file: URL?
    private var destination: TextDestination?
    private var insertionProblem = "Das Zieltextfeld konnte nicht übernommen werden."
    private var practice = false
    private var operation = UUID()
    private var work: Task<Void, Never>?
    private var meter: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    /// The last paste, including its check and the clipboard restore. A newer paste waits for it,
    /// so it never mistakes the previous dictation for the clipboard it has to restore.
    private var lastInsertion: Task<String?, Never>?
    private let overlay = RecordingOverlay()
    init() {
        shortcut.onArm = { [weak self] in self?.startHolding(confirmed: false) }
        shortcut.onPress = { [weak self] in self?.confirmHolding() }
        shortcut.onRelease = { [weak self] in self?.finish() }
        shortcut.onCancel = { [weak self] in
            guard let self, self.recording else { return }
            self.cancel()
        }
        shortcut.onCancelKey = { [weak self] in
            guard let self, self.canCancel else { return }
            self.cancel()
        }
        shortcut.onUserInteraction = { [weak self] in
            guard let self, self.busy else { return }
            self.destination = nil
            self.insertionProblem =
                "Du hast während der Verarbeitung weitergearbeitet. Dein Text ist in Flype zum Kopieren bereit."
        }
        refreshPermissions()
        preloadSpeechModel()
        // Interrupted recordings are never retained as a history.
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("flype-mac-") && file.pathExtension == "caf" {
                try? fm.removeItem(at: file)
            }
        }
    }
    /// Loading Parakeet can take seconds the first time, so it happens at launch instead of after the first release.
    private func preloadSpeechModel() {
        guard DictationOptions.current().provider == .parakeet, ParakeetModelStore.isAvailable else { return }
        Task { try? await ParakeetSpeechEngine().prepare() }
    }
    func suspend() {
        shortcut.stop()
        shortcutReady = false
        cancel()
    }
    func refreshPermissions() {
        microphoneReady = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityReady = MacEnvironment.isSandboxed || AXIsProcessTrusted()
        shortcutReady = shortcut.start()
    }
    func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshPermissions()
        }
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    func openPrivacy(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + section) {
            NSWorkspace.shared.open(url)
        }
    }
    func startPractice() { startHolding(practice: true) }
    func pauseShortcut(_ paused: Bool) { shortcut.paused = paused }
    private func startHolding(practice: Bool = false, confirmed: Bool = true) {
        guard !recording, !busy else { return }
        guard microphoneReady else {
            status = "Erlaube Flype zuerst den Mikrofonzugriff unter Einrichtung."
            return
        }
        self.practice = practice
        let id = UUID()
        operation = id
        result = ""
        original = ""
        cleanupNotice = nil
        options = DictationOptions.current()
        let engine: any SpeechRecognitionEngine =
            options.provider == .parakeet && ParakeetModelStore.isAvailable
            ? ParakeetSpeechEngine() : AppleSpeechEngine(language: options.language)
        self.engine = engine
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("flype-mac-" + id.uuidString + ".caf")
        self.file = file
        do {
            let capture = MicrophoneCapture()
            self.capture = capture
            // Capture now, before awaiting model preparation. Release always closes this file immediately.
            try capture.start(url: file)
            recording = true
            AccountController.prepareCleanup(mode: options.mode)
            // Audio is already flowing while accessibility and dictionary reads run.
            TextDestination.exposeElectronText()
            let target = TextDestination.capture()
            destination = target.destination
            insertionProblem = target.problem ?? "Das Zieltextfeld konnte nicht übernommen werden."
            dictionary = try PersonalDictionaryStore.shared().snapshot()
            if confirmed { confirmHolding() }
            let correction = DictionaryCorrectionService()
            dictionaryCorrection = correction
            let dictionary = self.dictionary
            let language = options.language
            // Both load while the user is still speaking, not after the release.
            let preparation = Task {
                try await engine.prepare()
                if dictionary.entries.contains(where: { $0.enabled && $0.useForDictation }) {
                    await correction.prepare(language: language)
                }
            }
            self.preparation = preparation
            work = Task { [self] in
                do { try await preparation.value } catch { if operation == id { fail(error) } }
            }
            meter = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    self.level = min(1, (self.capture?.level ?? 0) * 12)
                    self.overlay.update(level: self.level)
                    try? await Task.sleep(for: .milliseconds(30))
                }
            }
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        } catch { fail(error) }
    }
    private func confirmHolding() {
        guard recording else { return }
        status = "Ich höre zu …"
        overlay.show { [weak self] in self?.cancel() }
        setCanCancel(true)
    }
    /// Frees the shortcut as soon as the paste is sent instead of after checking it.
    private func pasted(operation id: UUID) {
        guard operation == id else { return }
        busy = false
        timeout?.cancel()
        overlay.hide()
    }
    private func setCanCancel(_ value: Bool) {
        canCancel = value
        shortcut.cancelKeyActive = value
        overlay.setCanCancel(value)
    }

    func finish() {
        guard recording, let file, let engine, let preparation else { return }
        var contextTiming = DictationTiming()
        let dictionary = self.dictionary
        let options = self.options
        let correction = dictionaryCorrection
        destination = destination?.refreshed()
        let fieldContext = destination?.textBeforeCursor()
        let followingText = destination?.textAfterCursor()
        // Accessibility calls block until the target app answers, which some apps take long for.
        contextTiming.mark("fieldContext")
        let startTiming = contextTiming
        // Only the length, never the text: shows whether the target app exposes what is in front of the cursor.
        let id = operation
        recording = false
        busy = true
        meter?.cancel()
        timeout?.cancel()
        overlay.setStage(.recognizing)
        capture?.stop()
        capture = nil
        level = 0
        status = "Dein Text entsteht …"
        // Recognition, dictionary and cleanup share one limit, so the shortcut can never stay blocked.
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, self.operation == id, self.busy else { return }
            self.fail(MacError.timedOut)
        }
        work = Task {
            defer { try? FileManager.default.removeItem(at: file) }
            var timing = startTiming
            do {
                try await preparation.value
                try Task.checkCancellation()
                guard operation == id else { return }
                // Model and dictionary loading that was still running when the shortcut was released.
                timing.mark("preparation")
                var text = try await engine.transcribe(file: file).trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !text.isEmpty else { throw MacError.noSpeech }
                timing.mark("recognition")
                original = text
                text = dictionary.applyingAliases(to: text)
                let corrected = try await correction.correct(text, file: file, dictionary: dictionary)
                text = corrected.text
                timing.mark("dictionary")
                if AccountController.cleanupActive(mode: options.mode) {
                    overlay.setStage(.cleaning)
                    do {
                        guard let token = try await AccountController.cloudCleanupToken() else {
                            throw SupabaseAPI.Failure.unauthorized
                        }
                        text = try await TextCleanupService().clean(
                            text, dictionary: dictionary, language: options.language, cloudToken: token,
                            fieldContext: fieldContext, followingText: followingText, soundAlikes: corrected.soundAlikes
                        )
                    } catch is CancellationError { throw CancellationError() } catch {
                        guard operation == id else { return }
                        cleanupNotice =
                            (error as? SupabaseAPI.Failure) == .limitReached
                            ? SupabaseAPI.Failure.limitReached.errorDescription
                            : "Die Bereinigung ist gerade nicht verfügbar. Dein Originaltext ist bereit."
                    }
                    timing.mark("cleanup")
                }
                try Task.checkCancellation()
                guard operation == id else { return }
                setCanCancel(false)
                result = text
                if practice {
                    status = "Dein Text ist bereit."
                } else if MacEnvironment.isSandboxed {
                    let board = NSPasteboard.general
                    board.clearContents()
                    board.setString(text + " ", forType: .string)
                    status = "Dein Text liegt in der Zwischenablage. Füge ihn mit ⌘V ein."
                } else if let destination {
                    let separator = DictationFieldContext.separator(before: text, after: fieldContext)
                    let trailing = DictationFieldContext.trailingSeparator(after: text, following: followingText)
                    await lastInsertion?.value
                    guard operation == id, !Task.isCancelled else { return }
                    let payload = separator + text + trailing
                    let insertion = Task { [weak self] in
                        // The text is in the field once the paste is sent. The next recording may start then,
                        // while the paste is still being checked and the clipboard restored.
                        await destination.insert(payload) { self?.pasted(operation: id) }
                    }
                    lastInsertion = insertion
                    let problem = await insertion.value
                    timing.report("insert", characters: text.count)
                    guard operation == id, !Task.isCancelled else { return }
                    if let problem {
                        status = problem
                    } else {
                        status = String(format: L10n.text("Text an %@ übergeben."), destination.appName)
                    }
                } else {
                    status = insertionProblem
                }
                guard operation == id, !Task.isCancelled else { return }
                if busy { timing.report("insert", characters: text.count) }
                busy = false
                timeout?.cancel()
                overlay.hide()
                // Keep the last result in memory so it can be copied if an editor ignores an event.
                self.file = nil
                self.engine = nil
                self.preparation = nil
            } catch { if operation == id { fail(error) } }
        }
    }
    func useOriginal() {
        guard !original.isEmpty else { return }
        result = original
        cleanupNotice = nil
        status = "Dein Text ist bereit."
    }

    func cancel() {
        operation = UUID()
        setCanCancel(false)
        work?.cancel()
        preparation?.cancel()
        preparation = nil
        meter?.cancel()
        timeout?.cancel()
        capture?.stop()
        capture = nil
        if let engine { Task { await engine.cancel() } }
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        engine = nil
        recording = false
        busy = false
        // Discarded text never stays behind for "Compare original".
        original = ""
        cleanupNotice = nil
        overlay.hide()
        status = "Alles bereit"
    }
    private func fail(_ error: Error) {
        cancel()
        status = error.localizedDescription
    }
}
private enum MacError: LocalizedError {
    case noSpeech, timedOut
    var errorDescription: String? {
        switch self {
        case .noSpeech: "Keine Sprache erkannt. Bitte prüfe dein Mikrofon und versuche es erneut."
        case .timedOut: "Die Verarbeitung hat zu lange gedauert. Bitte versuche es erneut."
        }
    }
}
@MainActor
private final class RecordingOverlayState: ObservableObject {
    enum Stage { case recording, recognizing, cleaning }
    @Published var level: Float = 0
    @Published var stage = Stage.recording
    @Published var canCancel = true
}

@MainActor
private final class RecordingOverlay {
    private var panel: NSPanel?
    private let state = RecordingOverlayState()
    func show(cancel: @escaping () -> Void) {
        hide()
        state.level = 0
        state.stage = .recording
        state.canCancel = true
        let content = NSHostingView(
            rootView: RecordingCapsule(state: state, language: .recognition(), cancel: cancel))
        let size = content.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        if let screen = NSScreen.main {
            panel.setFrameOrigin(
                NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 28))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }
    func setStage(_ stage: RecordingOverlayState.Stage) {
        state.level = 0
        state.stage = stage
        // Keep the nonactivating panel visible without taking focus from the target editor.
    }
    func setCanCancel(_ value: Bool) { state.canCancel = value }
    func update(level: Float) { state.level = level.isFinite ? min(1, max(0, level)) : 0 }
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecordingCapsule: View {
    @ObservedObject var state: RecordingOverlayState
    let language: FlypeLanguage
    let cancel: () -> Void
    @State private var hovering = false
    private var hint: String {
        MacEnvironment.isSandboxed
            ? L10n.text("Loslassen zum Kopieren")
            : String(format: L10n.text("%@ loslassen zum Einfügen"), DictationKey.current().name)
    }
    var body: some View {
        HStack(spacing: 15) {
            if state.stage == .recording {
                // Display only: releasing the key inserts, and the menu bar offers ending for VoiceOver.
                Image(systemName: "waveform").font(.system(size: 16, weight: .medium))
                    .frame(width: 38, height: 38)
                    .background(FlypeDesign.soft, in: Circle())
                    .overlay(
                        Circle().stroke(FlypeDesign.accent.opacity(0.75), lineWidth: 2 + CGFloat(state.level) * 5)
                    )
                    .foregroundStyle(FlypeDesign.accent)
                    .accessibilityHidden(true)
            } else {
                ProgressView().controlSize(.small).frame(width: 38, height: 38).accessibilityHidden(true)
            }
            // Every text stays in the layout, so the capsule keeps its width and the button its place.
            ZStack(alignment: .leading) {
                labels("Ich höre zu …", detail: hint, shown: state.stage == .recording)
                labels(
                    "Dein Text entsteht …", detail: L10n.text("Sprache wird erkannt"),
                    shown: state.stage == .recognizing)
                labels("Dein Text entsteht …", detail: L10n.text("Wird bereinigt"), shown: state.stage == .cleaning)
            }
            Text(verbatim: language.rawValue.uppercased()).font(.system(size: 11, weight: .medium)).foregroundStyle(
                .secondary)
            Button(action: cancel) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(FlypeDesign.ink.opacity(hovering ? 0.14 : 0.07), in: Circle())
                    .contentShape(Circle())
            }.buttonStyle(.plain).foregroundStyle(FlypeDesign.ink.opacity(hovering ? 1 : 0.68))
                .onHover { hovering = $0 }
                .help(L10n.text("Abbrechen"))
                .accessibilityLabel(L10n.text("Abbrechen"))
                .opacity(state.canCancel ? 1 : 0)
                .disabled(!state.canCancel)
        }.padding(.leading, 20).padding(.trailing, 18).padding(.vertical, 14)
            .background(FlypeDesign.surface, in: Capsule()).padding(7).fixedSize()
    }
    private func labels(_ title: String, detail: String, shown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text(title)).font(.system(size: 14, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityHidden(!shown)
    }
}
