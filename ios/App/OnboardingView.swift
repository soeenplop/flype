import AVFoundation
import FlypeCore
import SwiftUI
import UIKit

struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var dictation: DictationController
    let onIncomingURL: (URL) -> Void
    let onPause: () -> Void
    let onFinish: (Int) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var askingPermission = false
    @State private var settingsFailed = false
    @State private var practiceText = ""
    @State private var practiceStarted = Date()
    @State private var keyboardDetected = false
    @State private var sawPracticeResult = false
    @State private var practiceBaseline = ""
    @AppStorage("speechProvider") private var provider = SpeechProvider.parakeet.rawValue
    @AppStorage("interfaceLanguage", store: FlypePreferences.defaults) private var interfaceLanguage = "system"
    @FocusState private var practiceFocused: Bool
    @ScaledMetric private var instructionBadgeSize = 28.0

    private let accent = FlypeDesign.accent
    private let paper = FlypeDesign.paper
    private var step: OnboardingProgress.Step { state.progress.step }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("Schritt") + " \(step.rawValue + 1) / \(OnboardingProgress.Step.allCases.count)")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        ProgressView(value: Double(step.rawValue + 1), total: 6).tint(accent)
                    }
                    header
                    content
                    if settingsFailed {
                        hint(
                            "Öffne die Einstellungen bitte direkt über das Zahnrad auf deinem Home-Bildschirm.",
                            symbol: "info.circle")
                    }
                }
                .frame(maxWidth: 640, alignment: .leading).padding(20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(paper)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(L10n.text("Flype einrichten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step != .welcome {
                        Button {
                            practiceFocused = false
                            state.progress.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel(L10n.text("Vorheriger Schritt")).disabled(dictation.busy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("Später")) {
                        practiceFocused = false
                        onPause()
                    }.disabled(dictation.busy || askingPermission)
                }
            }
        }
        .tint(accent)
        .interactiveDismissDisabled()
        .onOpenURL(perform: onIncomingURL)
        .environment(\.locale, Locale(identifier: FlypeLanguage.interface().localeIdentifier))
        .id(interfaceLanguage)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { microphone = AVAudioApplication.shared.recordPermission }
        }
        .onChange(of: step) { _, value in
            practiceFocused = false
            if value == .practice {
                practiceStarted = Date()
                sawPracticeResult = false
                keyboardDetected = false
            }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        .onChange(of: practiceText) { _, _ in checkPracticeResult() }
        .onChange(of: dictation.phase) { _, phase in
            if step == .practice && phase == .preparing {
                practiceBaseline = practiceText
                sawPracticeResult = false
            }
        }
        .onChange(of: dictation.published) { _, published in
            if step == .practice && published {
                sawPracticeResult = true
                checkPracticeResult()
            }
        }
        .task(id: step) {
            guard step == .practice else { return }
            practiceStarted = Date()
            while !Task.isCancelled {
                if let seen = try? VoiceSessionStore.shared().lastKeyboardSeen(),
                    OnboardingProgress.keyboardWasSeen(seen, since: practiceStarted)
                {
                    keyboardDetected = true
                    if !state.progress.keyboardAcknowledged { state.progress.keyboardAcknowledged = true }
                    if !state.progress.fullAccessAcknowledged { state.progress.fullAccessAcknowledged = true }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(accent)
                .frame(width: 46, height: 46)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(title)).font(.title2.weight(.semibold).leading(.tight))
                    .tracking(-0.4).accessibilityAddTraits(.isHeader)
                Text(L10n.text(subtitle)).font(.subheadline).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            card {
                feature(
                    "Deine neue Tastatur.", "Vertraute Tasten, Wortvorschläge und Akzente beim Gedrückthalten.",
                    symbol: "keyboard")
                Divider()
                feature(
                    "Mit deiner Stimme schreiben",
                    "In der Tastatur starten, sprechen, stoppen. Der Text wird automatisch eingefügt.", symbol: "mic")
                Divider()
                feature(
                    "Deine Stimme bleibt auf deinem Gerät.",
                    "Aufnahmen werden auf deinem Gerät verarbeitet.", symbol: "lock")
            }
            DisclosureGroup(L10n.text("Sprachen")) {
                FlypeLanguageCard(locked: dictation.busy || dictation.sessionActive).padding(.top, 10)
            }.font(.subheadline)
            hint("Du kannst jederzeit pausieren und später weitermachen.", symbol: "clock")
        case .keyboard:
            card {
                instruction(
                    1, "Öffne die Einstellungen",
                    "Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur hinzufügen → Flype")
                instruction(2, "Aktiviere Flype", "Wähle Flype aus und kehre danach in diese App zurück.")
                settingsButton
            }
            hint("Falls Flype noch fehlt, öffne die App einmal und versuche es erneut.", symbol: "info.circle")
        case .fullAccess:
            card {
                instruction(1, "Öffne die Flype-Tastatur", "Einstellungen → Allgemein → Tastatur → Tastaturen → Flype")
                instruction(
                    2, "Erlaube vollen Zugriff",
                    "Aktiviere „Vollen Zugriff erlauben“ und bestätige den Hinweis von iOS.")
                settingsButton
            }
            hint(
                "Das verbindet die Tastatur mit deinen Transkriptionen und deinem Wörterbuch. Ohne Freigabe kannst du weiterhin tippen.",
                symbol: "keyboard")
            DisclosureGroup(L10n.text("Was bedeutet die Warnung von iOS?")) {
                Text(
                    L10n.text(
                        "Voller Zugriff erlaubt Tastaturen grundsätzlich eine Netzwerkverbindung. Flype überträgt deine Tastatureingaben und Aufnahmen nicht an einen Server."
                    )
                )
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 10)
            }
        case .microphone:
            card {
                feature(
                    microphone == .granted ? "Mikrofon ist bereit" : "Mikrofon erlauben.",
                    microphone == .granted
                        ? "Aufnahmen werden auf deinem Gerät verarbeitet."
                        : "Erlaube Flype das Mikrofon. Deine Aufnahme wird auf diesem Gerät verarbeitet.", symbol: "mic"
                )
                if microphone == .denied {
                    hint(
                        "Aktiviere das Mikrofon in den Flype-Einstellungen, wenn du die Spracheingabe nutzen möchtest.",
                        symbol: "mic.slash")
                    settingsButton
                } else if microphone != .granted {
                    Button {
                        askingPermission = true
                        Task {
                            _ = await AVAudioApplication.requestRecordPermission()
                            microphone = AVAudioApplication.shared.recordPermission
                            askingPermission = false
                        }
                    } label: {
                        Label(L10n.text("Mikrofon erlauben"), systemImage: "mic")
                            .frame(maxWidth: .infinity).padding(
                                .vertical, 5)
                    }
                    .buttonStyle(OnboardingActionStyle()).disabled(askingPermission)
                }
            }
            hint(
                "Nach dem ersten Start bleibt das Mikrofon für weitere Transkriptionen bereit, ohne dass zwischen den Transkriptionen Audio gespeichert wird. Das endet, wenn du es in Flype ausschaltest, dein Gerät sperrst oder die Flype-Tastatur fünf Minuten nicht nutzt.",
                symbol: "info.circle")
            if provider == SpeechProvider.apple.rawValue {
                hint(
                    "Bei der ersten Transkription werden bei Bedarf Sprachdaten geladen. Danach läuft die Erkennung lokal.",
                    symbol: "arrow.down.circle")
            }
        case .practice:
            card {
                instruction(1, "Tippe ins Testfeld", "Halte die Globustaste gedrückt und wähle Flype.")
                if state.progress.fullAccessAcknowledged && microphone == .granted {
                    instruction(
                        2, "Deine ersten Worte.",
                        "Öffne die Flype-Tastatur. Tippe auf das Mikrofon neben der Leertaste, sprich einen Satz und stoppe die Aufnahme."
                    )
                    hint(
                        "Beim ersten Start öffnet sich Flype kurz. Kehre gegebenenfalls zum Textfeld zurück. Weitere Transkriptionen startest du direkt in der Tastatur.",
                        symbol: "info.circle")
                } else {
                    instruction(
                        2, "Einfach ausprobieren.",
                        "Tippe ein paar Wörter. Halte einen Buchstaben gedrückt und ziehe zu einem Akzent oder Umlaut.")
                }
            }
            TextField(L10n.text("Hier ist Platz für deine Worte."), text: $practiceText, axis: .vertical)
                .lineLimit(2...4).focused($practiceFocused).padding(16)
                .background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("onboardingPractice")
            if keyboardDetected {
                Label(L10n.text("Flype-Tastatur erkannt"), systemImage: "checkmark.circle").font(.footnote)
                    .foregroundStyle(accent)
            }
            if state.progress.dictationTestSucceeded {
                Label(L10n.text("Dein Text ist eingefügt."), systemImage: "checkmark.circle.fill").font(.subheadline)
                    .foregroundStyle(accent)
            }
            if dictation.busy {
                Text(L10n.text(dictation.status)).font(.footnote).foregroundStyle(.secondary)
                Button(L10n.text("Abbrechen"), role: .cancel) { dictation.cancel() }
            } else if dictation.phase == .failed {
                // The keyboard itself shows no messages, so a failed attempt has to be explained here.
                hint(dictation.status, symbol: "exclamationmark.circle")
            }
            DisclosureGroup(L10n.text("Hilfe bei der ersten Transkription")) {
                VStack(alignment: .leading, spacing: 14) {
                    help("Mikrofon ist ausgegraut?", "Prüfe vollen Zugriff und Mikrofonzugriff in den Einstellungen.")
                    help(
                        "Die Apple-Tastatur erscheint?",
                        "Bei Passwörtern und in manchen Apps ist das vorgesehen. Teste Flype in einem normalen Textfeld."
                    )
                    help("Der orange Punkt", "Der Punkt zeigt ein aktives Mikrofon. Du kannst es in Flype ausschalten.")
                }.padding(.top, 10)
            }
        case .finish:
            card {
                feature(
                    "Deine Tastatur ist bereit.",
                    "Du kannst mit Flype schreiben. Einrichtung und Hilfe findest du jederzeit in den Einstellungen.",
                    symbol: "keyboard")
                Divider()
                feature(
                    "Deine Wörter", "Für Namen, Firmen und Begriffe, die Flype genauso schreiben soll.", symbol: "book")
                Divider()
                feature("Dein Schreibstil", "Setzt Satzzeichen und lässt Füllwörter weg.", symbol: "sparkles")
            }
            if let explanation = TextCleanupService.availabilityMessage() {
                hint(explanation, symbol: "sparkles")
            }
            HStack {
                Button(L10n.text("Deine Wörter")) { complete(destination: 3) }.frame(minHeight: 44)
                Spacer()
                Button(L10n.text("Einstellungen")) { complete(destination: 4) }.frame(minHeight: 44)
            }
            .font(.subheadline)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if step == .keyboard {
                confirmation("Ich habe Flype als Tastatur hinzugefügt", isOn: $state.progress.keyboardAcknowledged)
            } else if step == .fullAccess {
                confirmation("Ich habe vollen Zugriff erlaubt", isOn: $state.progress.fullAccessAcknowledged)
            }
            Button(action: advance) {
                Text(L10n.text(primaryTitle)).font(.headline).frame(maxWidth: .infinity)
            }
            // Skipping the test is possible, but the test is what this step is for.
            .buttonStyle(OnboardingActionStyle(secondary: step == .practice && !state.progress.dictationTestSucceeded))
            .disabled(!canAdvance || dictation.busy || askingPermission)
            if step == .fullAccess || (step == .microphone && microphone != .granted) {
                Button(L10n.text(step == .fullAccess ? "Zunächst nur tippen" : "Mikrofon später erlauben")) {
                    practiceFocused = false
                    state.progress.advance(skipOptional: true)
                }.font(.subheadline).frame(minHeight: 44).disabled(dictation.busy || askingPermission)
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity).background(.regularMaterial)
    }

    private var canAdvance: Bool {
        switch step {
        case .keyboard: state.progress.keyboardAcknowledged
        case .fullAccess: state.progress.fullAccessAcknowledged
        case .microphone: microphone == .granted
        default: true
        }
    }
    private var primaryTitle: String {
        switch step {
        case .welcome: "Los geht’s"
        case .practice: state.progress.dictationTestSucceeded ? "Weiter" : "Ohne Test weiter"
        case .finish: "Zur Übersicht"
        default: "Weiter"
        }
    }
    private var title: String {
        switch step {
        case .welcome: "Willkommen bei Flype."
        case .keyboard: "Deine neue Tastatur."
        case .fullAccess: "Spracheingabe möglich machen."
        case .microphone: "Deine Stimme. Deine Entscheidung."
        case .practice: "Probier Flype aus."
        case .finish: "Dein Flype. Dein Schreibfluss."
        }
    }
    private var subtitle: String {
        switch step {
        case .welcome: "Wir richten Flype gemeinsam ein."
        case .keyboard: "Einmal hinzufügen. Überall schreiben."
        case .fullAccess: "Verbinde deine Tastatur mit Flype."
        case .microphone: "Du entscheidest, wann du sprichst."
        case .practice: "Ein kurzer Test. Deine ersten Worte."
        case .finish: "Du kannst jetzt mit Flype schreiben."
        }
    }
    private var symbol: String {
        switch step {
        case .welcome: "waveform"
        case .keyboard: "keyboard"
        case .fullAccess: "keyboard.badge.ellipsis"
        case .microphone: "mic"
        case .practice: "text.cursor"
        case .finish: "checkmark.seal"
        }
    }
    private func advance() {
        practiceFocused = false
        if step == .finish {
            complete(destination: 0)
        } else {
            state.progress.advance(microphoneGranted: microphone == .granted, skipOptional: step == .practice)
        }
    }
    private func complete(destination: Int) {
        guard state.progress.complete() else { return }
        practiceFocused = false
        onFinish(destination)
    }
    private func checkPracticeResult() {
        guard step == .practice,
            OnboardingProgress.confirmsPracticeInsertion(
                before: practiceBaseline, after: practiceText,
                dictation: dictation.transcript, published: dictation.published,
                sawCurrentPublication: sawPracticeResult)
        else { return }
        if !state.progress.dictationTestSucceeded { state.progress.dictationTestSucceeded = true }
    }
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsFailed = true
            return
        }
        UIApplication.shared.open(url) { success in settingsFailed = !success }
    }
    private var settingsButton: some View {
        Button(action: openSettings) {
            Label(L10n.text("Einstellungen öffnen"), systemImage: "gearshape").frame(maxWidth: .infinity).padding(
                .vertical, 5)
        }
        .buttonStyle(OnboardingActionStyle(secondary: true))
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).padding(18)
            .frame(maxWidth: .infinity, alignment: .leading).background(
                FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func feature(_ title: String, _ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(accent).frame(width: 25).accessibilityHidden(true)
            help(title, text)
        }
    }
    private func help(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.text(title)).font(.subheadline.weight(.semibold))
            Text(L10n.text(text)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func instruction(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number)).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                .frame(width: instructionBadgeSize, height: instructionBadgeSize)
                .background(accent.opacity(0.08), in: Circle())
            help(title, text)
        }
    }
    private func hint(_ text: String, symbol: String) -> some View {
        Label {
            Text(L10n.text(text)).font(.footnote).foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol).foregroundStyle(accent)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    private func confirmation(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(L10n.text(title), isOn: isOn).font(.subheadline.weight(.medium)).tint(accent)
            .padding(.vertical, 4)
    }
}

/// Owns both surface and foreground, including the disabled state. Native prominent
/// styles can otherwise dim a custom foreground against a different system fill.
private struct OnboardingActionStyle: ButtonStyle {
    var secondary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 18).padding(.vertical, 17)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .opacity(isEnabled && configuration.isPressed ? 0.85 : 1)
    }
    private var foreground: Color {
        if !isEnabled {
            return scheme == .dark
                ? Color(red: 0.76, green: 0.74, blue: 0.79) : Color(red: 0.36, green: 0.33, blue: 0.39)
        }
        return secondary ? Color.primary : FlypeDesign.onAccent
    }
    private var background: Color {
        if !isEnabled {
            return scheme == .dark
                ? Color(red: 0.22, green: 0.20, blue: 0.24) : Color(red: 0.89, green: 0.87, blue: 0.91)
        }
        if secondary {
            return scheme == .dark
                ? Color(red: 0.24, green: 0.21, blue: 0.29) : Color(red: 0.91, green: 0.88, blue: 0.96)
        }
        return FlypeDesign.accent
    }
}
