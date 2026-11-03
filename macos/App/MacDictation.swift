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
    private let overlay = RecordingOverlay()
    init() {
        shortcut.onArm = { [weak self] in self?.startHolding(confirmed: false) }
        shortcut.onPress = { [weak self] in self?.confirmHolding() }
        shortcut.onRelease = { [weak self] in self?.finish() }
        shortcut.onCancel = { [weak self] in
            guard let self, self.recording else { return }
            self.cancel()
        }
        shortcut.onUserInteraction = { [weak self] in
            guard let self, self.busy else { return }
            self.destination = nil
            self.insertionProblem =
                "Du hast während der Verarbeitung weitergearbeitet. Dein Text ist in Flype zum Kopieren bereit."
        }
        refreshPermissions()
        // Interrupted recordings are never retained as a history.
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("flype-mac-") && file.pathExtension == "caf" {
                try? fm.removeItem(at: file)
            }
        }
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
            // Audio is already flowing while accessibility and dictionary reads run.
            TextDestination.exposeElectronText()
            let target = TextDestination.capture()
            destination = target.destination
            insertionProblem = target.problem ?? "Das Zieltextfeld konnte nicht übernommen werden."
            dictionary = try PersonalDictionaryStore.shared().snapshot()
            if confirmed { confirmHolding() }
            let preparation = Task { try await engine.prepare() }
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
        overlay.show { [weak self] in self?.finish() }
    }

    func finish() {
        guard recording, let file, let engine, let preparation else { return }
        let dictionary = self.dictionary
        let options = self.options
        destination = destination?.refreshed()
        let fieldContext = destination?.textBeforeCursor()
        // Only the length, never the text: shows whether the target app exposes what is in front of the cursor.
        let id = operation
        recording = false
        busy = true
        meter?.cancel()
        timeout?.cancel()
        overlay.processing()
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
            do {
                try await preparation.value
                try Task.checkCancellation()
                guard operation == id else { return }
                var text = try await engine.transcribe(file: file).trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !text.isEmpty else { throw MacError.noSpeech }
                original = text
                text = dictionary.applyingAliases(to: text)
                let service = DictionaryCorrectionService()
                await service.prepare(language: options.language)
                text = try await service.correct(text, file: file, dictionary: dictionary).text
                if options.mode == .cleaned {
                    do {
                        let token = try? await AccountController.cloudCleanupToken()
                        text = try await TextCleanupService().clean(
                            text, dictionary: dictionary, language: options.language, cloudToken: token,
                            fieldContext: fieldContext)
                    } catch is CancellationError { throw CancellationError() } catch {
                        guard operation == id else { return }
                        cleanupNotice =
                            (error as? SupabaseAPI.Failure) == .limitReached
                            ? SupabaseAPI.Failure.limitReached.errorDescription
                            : "Die Bereinigung ist gerade nicht verfügbar. Dein Originaltext ist bereit."
                    }
                }
                try Task.checkCancellation()
                guard operation == id else { return }
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
                    let problem = await destination.insert(separator + text + " ")
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
    @Published var level: Float = 0
    @Published var processing = false
}

@MainActor
private final class RecordingOverlay {
    private var panel: NSPanel?
    private let state = RecordingOverlayState()
    func show(stop: @escaping () -> Void) {
        hide()
        state.level = 0
        state.processing = false
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 84), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(
            rootView: RecordingCapsule(state: state, language: .recognition(), stop: stop))
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - 145, y: screen.visibleFrame.minY + 28))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }
    func processing() {
        state.level = 0
        state.processing = true
        // Keep the nonactivating panel visible without taking focus from the target editor.
    }
    func update(level: Float) { state.level = level.isFinite ? min(1, max(0, level)) : 0 }
    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct RecordingCapsule: View {
    @ObservedObject var state: RecordingOverlayState
    let language: FlypeLanguage
    let stop: () -> Void
    var body: some View {
        HStack(spacing: 15) {
            if state.processing {
                ProgressView().controlSize(.small).frame(width: 38, height: 38)
                    .accessibilityLabel(L10n.text("Dein Text entsteht …"))
            } else {
                Button(action: stop) {
                    Image(systemName: "waveform").font(.system(size: 16, weight: .medium))
                        .frame(width: 38, height: 38)
                        .background(FlypeDesign.soft, in: Circle())
                        .overlay(
                            Circle().stroke(FlypeDesign.accent.opacity(0.75), lineWidth: 2 + CGFloat(state.level) * 5))
                }.buttonStyle(.plain).foregroundStyle(FlypeDesign.accent)
                    .accessibilityLabel(L10n.text("Transkription beenden"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(state.processing ? "Dein Text entsteht …" : "Ich höre zu …"))
                    .font(.system(size: 14, weight: .medium))
                if !state.processing {
                    Text(
                        MacEnvironment.isSandboxed
                            ? L10n.text("Loslassen zum Kopieren")
                            : String(format: L10n.text("%@ loslassen zum Einfügen"), DictationKey.current().name)
                    )
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text(verbatim: language.rawValue.uppercased()).font(.system(size: 11, weight: .medium)).foregroundStyle(
                .secondary)
        }.padding(.horizontal, 20).padding(.vertical, 14)
            .background(FlypeDesign.surface, in: Capsule()).padding(7)
    }
}
