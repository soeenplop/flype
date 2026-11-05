import AVFoundation
import FlypeCore
import SwiftUI
import UIKit

private let ink = FlypeDesign.ink
private let plum = FlypeDesign.accent
private let paper = FlypeDesign.paper

struct HomeView: View {
    @StateObject private var account = AccountController()
    @StateObject private var dictation = DictationController()
    @StateObject private var onboarding = OnboardingState()
    @StateObject private var speechSetup = SpeechSetupController()
    @State private var showingOnboarding = false
    @State private var hasBootstrapped = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0
    @State private var pendingStartURL: URL?
    @AppStorage("dictationMode") private var mode = "cleaned"
    @AppStorage("speechProvider") private var provider = SpeechProvider.parakeet.rawValue

    @State private var showingAccount = false
    @State private var showingPractice = false
    @AppStorage("interfaceLanguage", store: FlypePreferences.defaults) private var interfaceLanguage = "system"

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                FlypePage {
                    HStack {
                        FlypeBrand()
                        Spacer()
                        Button {
                            showingAccount = true
                        } label: {
                            Image(systemName: "person.crop.circle").font(.title2)
                                .frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel(L10n.text("Dein Konto"))
                    }.padding(.bottom, 10)
                    if dictation.phase != .failed {
                        Label(
                            L10n.text(onboarding.progress.completed ? "Alles bereit" : "Willkommen bei Flype."),
                            systemImage: onboarding.progress.completed ? "checkmark.circle" : "circle.dotted"
                        )
                        .font(.footnote).foregroundStyle(FlypeDesign.accent)
                    }
                    Text(L10n.text("Einfach\nlossprechen."))
                        .font(.largeTitle.weight(.semibold).leading(.tight))
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.text("Schreib, wie du sprichst.\nDirekt mit deiner Flype-Tastatur."))
                        .font(.body).foregroundStyle(.secondary)
                    keyboardStatusCard
                    if !dictation.transcript.isEmpty { LastDictationCard(dictation: dictation) }
                    VStack(spacing: 0) {
                        Button {
                            selectedTab = 4
                        } label: {
                            FlypeRow(
                                title: "Dein Schreibstil", symbol: "sparkles",
                                detail: (DictationMode(rawValue: mode) ?? .cleaned).title)
                        }.buttonStyle(.plain)
                        Divider()
                        Button {
                            selectedTab = 3
                        } label: {
                            FlypeRow(title: "Deine Wörter", symbol: "book")
                        }.buttonStyle(.plain)
                    }
                    FlypePrivacyNote()
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .tint(FlypeDesign.accent)
            .tabItem { Label(L10n.text("Start"), systemImage: "house") }.tag(0)
            NavigationStack { DictionaryView() }.tint(FlypeDesign.accent)
                .tabItem { Label(L10n.text("Wörter"), systemImage: "book") }.tag(3)
            NavigationStack {
                ProcessingSettingsView(
                    dictation: dictation, account: account, speechSetup: speechSetup,
                    onSetup: { presentOnboarding(restart: true) })
            }
            .tint(FlypeDesign.accent)
            .tabItem { Label(L10n.text("Einstellungen"), systemImage: "slider.horizontal.3") }.tag(4)
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay {
            if speechSetup.requirement == .choice || speechSetup.requirement == .downloadRequired {
                SpeechSetupView(setup: speechSetup).tint(FlypeDesign.accent)
            }
        }
        .id(interfaceLanguage)
        .environment(\.locale, Locale(identifier: FlypeLanguage.interface().localeIdentifier))
        .sheet(isPresented: $showingAccount) {
            NavigationStack {
                AccountView(account: account).toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Fertig")) { showingAccount = false }
                    }
                }
            }
            .tint(FlypeDesign.accent)
        }
        .sheet(isPresented: $showingPractice) {
            NavigationStack {
                KeyboardPracticeView(
                    dictation: dictation,
                    onSetup: {
                        showingPractice = false
                        presentOnboarding(restart: true)
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Fertig")) { showingPractice = false }
                    }
                }
            }
            .tint(FlypeDesign.accent)
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(
                state: onboarding, dictation: dictation,
                onIncomingURL: handleIncomingURL,
                onPause: { showingOnboarding = false },
                onFinish: { destination in
                    selectedTab = destination == 1 ? 0 : destination
                    showingOnboarding = false
                })
        }
        .tint(FlypeDesign.navigationTint)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { dictation.handleBackground() }
            if phase == .active {
                consumeStartRequest()
                Task { await speechSetup.refresh() }
                Task { await account.sync() }
            }
        }
        .onOpenURL(perform: handleIncomingURL)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            if !dictation.busy { Task { try? await ParakeetSpeechEngine.unload() } }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
        ) { _ in
            dictation.handleProtectedDataLoss()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                type == AVAudioSession.InterruptionType.began.rawValue
            {
                dictation.interruptAudio()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                    || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
            {
                dictation.interruptAudio()
            }
        }
        .onAppear {
            // A full-screen setup cover may repeat appearance on dismissal.
            // Never clear an active recording or restart diagnostics on that return.
            guard !hasBootstrapped else { return }
            hasBootstrapped = true
            DictationController.clearAbandonedAudio()
            #if DEBUG
                if !ProcessingDiagnostics.runIfRequested() { dictation.runDiagnosticsIfRequested() }
                let diagnostic = ProcessInfo.processInfo.arguments.contains {
                    $0.hasPrefix("--verify-") || $0.hasPrefix("--diagnose-")
                }
                if diagnostic { return }
            #endif
            Task {
                await speechSetup.refresh()
                presentOnboardingIfNeeded()
            }
        }
        .onChange(of: speechSetup.requirement) { _, _ in presentOnboardingIfNeeded() }
    }

    private func handleIncomingURL(_ url: URL) {
        recordKeyboardStartStatus("received", validURL: KeyboardStartRequest.requestID(from: url) != nil)
        pendingStartURL = url
        if scenePhase == .active { consumeStartRequest() }
    }

    /// The recognizer comes first: the setup steps end with a dictation test that depends on it.
    private func presentOnboardingIfNeeded() {
        guard speechSetup.requirement == .ready, onboarding.progress.shouldPresentAutomatically, !showingOnboarding
        else { return }
        presentOnboarding()
    }

    private func presentOnboarding(restart: Bool = false) {
        guard !dictation.busy else { return }
        onboarding.begin(restart: restart)
        showingOnboarding = true
    }

    private func consumeStartRequest() {
        guard let url = pendingStartURL else { return }
        pendingStartURL = nil
        guard let id = KeyboardStartRequest.requestID(from: url) else {
            recordKeyboardStartStatus("invalid-url")
            return
        }
        Task {
            if speechSetup.requirement == .checking { await speechSetup.refresh() }
            // The setup screen is in front; the microphone stays off until a recognizer exists.
            guard speechSetup.requirement == .ready else {
                recordKeyboardStartStatus("setup-required")
                return
            }
            startDictation(requestID: id)
        }
    }

    private func startDictation(requestID id: UUID) {
        do {
            guard let request = try KeyboardStartStore.shared().consumeRequest(id: id) else {
                recordKeyboardStartStatus("request-unavailable")
                return
            }
            recordKeyboardStartStatus(dictation.busy ? "already-busy" : "starting")
            selectedTab = 0
            // Keep the practice field alive for dictation into this app. An
            // external keyboard start otherwise takes priority over setup.
            if showingOnboarding && onboarding.progress.step != .practice { showingOnboarding = false }
            #if DEBUG
                PreviousAppReturn.shared.capture(for: request.id, applicationID: request.returnApplicationID)
            #endif
            dictation.start(fromKeyboard: true, keyboardRequestID: request.id)
        } catch {
            // An invalid/unavailable request must never activate the microphone.
            recordKeyboardStartStatus("store-error")
        }
    }

    private func recordKeyboardStartStatus(_ stage: String, validURL: Bool = true) {
        #if DEBUG
            // Technical routing status only: no URLs, request IDs, audio or dictated text.
            let status: [String: String] = [
                "stage": stage, "validURL": String(validURL), "scenePhase": String(describing: scenePhase),
                "dictationPhase": String(describing: dictation.phase),
                "timestamp": String(Date().timeIntervalSince1970),
            ]
            if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                let data = try? JSONEncoder().encode(status)
            {
                try? data.write(to: cache.appendingPathComponent("keyboard-start-status.json"), options: .atomic)
            }
        #endif
    }

    private var keyboardStatusTitle: String {
        switch dictation.phase {
        case .preparing: "Flype wird vorbereitet"
        case .recording: "Aufnahme läuft"
        case .transcribing, .cleaning: "Deine Transkription wird verarbeitet"
        case .failed: "Transkription nicht abgeschlossen"
        default:
            dictation.sessionActive
                ? "Mikrofon ist bereit"
                : (onboarding.progress.completed ? "Deine Tastatur ist bereit." : "Deine neue Tastatur.")
        }
    }

    private var keyboardStatusDetail: String {
        if dictation.phase == .recording {
            return "Wechsle zurück zu deiner App und stoppe die Aufnahme in der Flype-Tastatur."
        }
        if dictation.busy { return "Deine Aufnahme bleibt auf deinem Gerät." }
        if dictation.phase == .failed { return "Starte die Transkription in der Tastatur erneut." }
        if dictation.sessionActive { return "Weitere Transkriptionen direkt starten und stoppen." }
        return onboarding.progress.completed
            ? "Tippe beim Schreiben auf das Mikrofon neben der Leertaste." : "Wir richten Flype gemeinsam ein."
    }

    private var keyboardStatusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: dictation.sessionActive ? "waveform" : "keyboard")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(dictation.sessionActive ? Color.green : plum)
                    .frame(width: 44, height: 44)
                    .background(
                        (dictation.sessionActive ? Color.green : plum).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(keyboardStatusTitle))
                        .font(.headline)
                    Text(L10n.text(keyboardStatusDetail))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if dictation.busy || dictation.phase == .failed {
                HStack(alignment: .top, spacing: 10) {
                    if dictation.phase == .recording {
                        Circle().fill(.red).frame(width: 7, height: 7).padding(.top, 5)
                    } else if dictation.busy {
                        ProgressView().controlSize(.small).tint(plum)
                    } else {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(plum)
                    }
                    Text(L10n.text(dictation.status))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("dictationStatus")
                }
            }
            Button {
                if onboarding.progress.completed { showingPractice = true } else { presentOnboarding() }
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.text(onboarding.progress.completed ? "Hier ausprobieren" : "Einrichtung fortsetzen"))
                    Image(systemName: "arrow.right")
                }
            }.buttonStyle(FlypePrimaryButtonStyle()).fixedSize(horizontal: true, vertical: true)
                .disabled(dictation.busy)
            if dictation.sessionActive {
                Divider()
                Text(
                    L10n.text(
                        "Nach dem ersten Start bleibt das Mikrofon für weitere Transkriptionen bereit, ohne dass zwischen den Transkriptionen Audio gespeichert wird. Das endet, wenn du es in Flype ausschaltest, dein Gerät sperrst oder die Flype-Tastatur fünf Minuten nicht nutzt."
                    )
                )
                .font(.footnote).foregroundStyle(.secondary)
                if dictation.busy {
                    Button(L10n.text("Abbrechen"), role: .cancel) { dictation.discardCurrent() }
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 4)
                }
                Button(L10n.text("Mikrofon ausschalten"), role: .destructive) { dictation.endSession() }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 4)
            } else if dictation.busy {
                Button(L10n.text("Abbrechen"), role: .cancel) { dictation.cancel() }.font(.subheadline)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 20))
    }

}

/// A way back to the text if inserting failed. It lives only in memory, so this is not a history.
private struct LastDictationCard: View {
    @ObservedObject var dictation: DictationController
    @State private var copied = false
    var body: some View {
        FlypeCard {
            Text(L10n.text("Letzte Transkription")).font(.headline).accessibilityAddTraits(.isHeader)
            Text(verbatim: dictation.transcript).font(.subheadline).lineLimit(8).textSelection(.enabled)
            if let notice = dictation.cleanupNotice {
                Text(L10n.text(notice)).font(.footnote).foregroundStyle(.secondary)
            }
            if !dictation.published, let notice = dictation.notice {
                Text(L10n.text(notice)).font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                Button(L10n.text(copied ? "Kopiert" : "Text kopieren")) {
                    UIPasteboard.general.string = dictation.transcript
                    copied = true
                }
                Spacer()
                Button(L10n.text("Löschen"), role: .destructive) { dictation.clearLastDictation() }
            }.font(.subheadline)
        }
        .onChange(of: dictation.transcript) { _, _ in copied = false }
    }
}

private struct KeyboardPracticeView: View {
    @ObservedObject var dictation: DictationController
    let onSetup: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        FlypePage {
            Text(L10n.text("Einmal ausprobieren.")).font(.title.weight(.semibold).leading(.tight))
            Text(L10n.text("Wähle Flype über die Globustaste und tippe auf das Mikrofon neben der Leertaste."))
                .foregroundStyle(.secondary)
            TextField(L10n.text("Hier ist Platz für deine Worte."), text: $text, axis: .vertical)
                .lineLimit(5...10).focused($focused).padding(18)
                .background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("keyboardPractice")
            // The keyboard itself shows no messages, so a failed attempt has to be explained here.
            if dictation.phase == .failed {
                Label(L10n.text(dictation.status), systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button(L10n.text("Einrichtung & Hilfe"), action: onSetup)
            FlypePrivacyNote()
        }.navigationTitle(L10n.text("Ausprobieren"))
            .navigationBarTitleDisplayMode(.inline)
    }
}
