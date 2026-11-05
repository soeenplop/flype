import AppKit
import FlypeCore
import SwiftUI

/// A single Window scene would otherwise quit the app with its window; the shortcut has to keep working.
private final class FlypeMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct FlypeMacApp: App {
    @NSApplicationDelegateAdaptor(FlypeMacAppDelegate.self) private var appDelegate
    @StateObject private var account = AccountController()
    @StateObject private var dictation = MacDictation()
    @StateObject private var speechSetup = SpeechSetupController()
    @Environment(\.openWindow) private var openWindow
    @AppStorage("dictationKey") private var dictationKey = Int(DictationKey.rightCommand.keyCode)
    init() {
        DictationMode.adoptCleanedDefault()
        SpeechProvider.adoptParakeetDefault()
    }

    var body: some Scene {
        Window("Flype", id: "main") {
            MacHomeView(account: account, dictation: dictation, speechSetup: speechSetup)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .frame(minWidth: 760, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    dictation.refreshPermissions()
                    Task { await speechSetup.refresh() }
                    Task { await account.sync() }
                }
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
                ) { _ in dictation.suspend() }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) {
                    _ in dictation.suspend()
                }
                .onReceive(
                    NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
                ) { _ in
                    dictation.refreshPermissions()
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    dictation.refreshPermissions()
                }
        }
        .defaultSize(width: 980, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("Einstellungen")) {
                    NotificationCenter.default.post(name: MacHomeView.showSettings, object: nil)
                }
                .keyboardShortcut(",")
            }
        }
        MenuBarExtra("Flype", systemImage: dictation.recording ? "waveform.circle.fill" : "waveform") {
            Text(L10n.text(dictation.status))
            Text(
                MacEnvironment.isSandboxed
                    ? L10n.text("⌃⌥ Leertaste zum Sprechen gedrückt halten")
                    : String(
                        format: L10n.text("Halte %@ beim Sprechen."),
                        (DictationKey(keyCode: dictationKey) ?? .rightCommand).name))
            if dictation.recording { Button(L10n.text("Transkription beenden")) { dictation.finish() } }
            if dictation.canCancel { Button(L10n.text("Abbrechen")) { dictation.cancel() } }
            Button(L10n.text("Flype öffnen")) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button(L10n.text("Flype beenden")) {
                dictation.cancel()
                NSApp.terminate(nil)
            }
        }
    }
}
private struct MacHomeView: View {
    static let showSettings = Notification.Name("one.binda.flype.showSettings")
    @ObservedObject var account: AccountController
    @ObservedObject var dictation: MacDictation
    @ObservedObject var speechSetup: SpeechSetupController
    @State private var selection = "home"
    @State private var confirmingModelDelete = false
    @State private var practice = false
    @AppStorage("dictationMode") private var mode = "cleaned"
    @AppStorage(CloudCleanup.consentKey) private var cloudConsent = false
    @AppStorage("speechProvider") private var provider = SpeechProvider.parakeet.rawValue
    @AppStorage("dictationKey") private var dictationKey = Int(DictationKey.rightCommand.keyCode)
    @AppStorage("interfaceLanguage", store: FlypePreferences.defaults) private var interfaceLanguage = "system"
    private var key: DictationKey { DictationKey(keyCode: dictationKey) ?? .rightCommand }
    private var ready: Bool { dictation.microphoneReady && dictation.accessibilityReady && dictation.shortcutReady }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 28) {
                FlypeBrand().padding(.horizontal, 16).padding(.top, 24)
                VStack(spacing: 5) {
                    sidebar("Start", symbol: "house", destination: "home")
                    sidebar("Wörter", symbol: "book", destination: "words")
                    sidebar("Einstellungen", symbol: "slider.horizontal.3", destination: "settings")
                }
                Spacer()
                Button {
                    selection = "account"
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "person.crop.circle").font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text("Dein Konto"))
                            Text(L10n.text("Auf allen Geräten")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(15).contentShape(Rectangle())
                        .background(
                            selection == "account" ? FlypeDesign.surface : .clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .foregroundStyle(selection == "account" ? FlypeDesign.accent : .primary)
                }.buttonStyle(.plain).accessibilityAddTraits(selection == "account" ? .isSelected : [])
            }.padding(10).background(FlypeDesign.soft).navigationSplitViewColumnWidth(205)
        } detail: {
            Group {
                switch selection {
                case "words": DictionaryView()
                case "account": AccountView(account: account)
                case "setup": setup
                case "settings": settings
                case "privacy": PrivacyView()
                default: overview
                }
            }.background(FlypeDesign.paper)
        }
        .tint(FlypeDesign.accent)
        .environment(\.locale, Locale(identifier: FlypeLanguage.interface().localeIdentifier))
        .id(interfaceLanguage)
        .overlay {
            if speechSetup.requirement == .choice || speechSetup.requirement == .downloadRequired {
                SpeechSetupView(setup: speechSetup).tint(FlypeDesign.accent)
            }
        }
        .task { await speechSetup.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Self.showSettings)) { _ in selection = "settings" }
        .onAppear { if !ready { selection = "setup" } }
    }
    private func sidebar(_ title: String, symbol: String, destination: String) -> some View {
        Button {
            selection = destination
            practice = false
        } label: {
            Label(L10n.text(title), systemImage: symbol)
                .font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(13).contentShape(Rectangle())
                .background(
                    selection == destination ? FlypeDesign.surface : .clear, in: RoundedRectangle(cornerRadius: 10)
                )
                .foregroundStyle(selection == destination ? FlypeDesign.accent : .primary)
        }.buttonStyle(.plain).accessibilityAddTraits(selection == destination ? .isSelected : [])
    }
    private var overview: some View {
        FlypePage {
            Label(
                L10n.text(ready ? "Alles bereit" : "Einrichtung fortsetzen"),
                systemImage: ready ? "checkmark.circle" : "circle"
            )
            .font(.footnote).foregroundStyle(FlypeDesign.accent).padding(.top, 22)
            Text(L10n.text("Deine Gedanken.\nDeine Worte."))
                .font(.largeTitle.weight(.semibold).leading(.tight))
            Text(
                MacEnvironment.isSandboxed
                    ? L10n.text("Halte ⌃⌥ Leertaste beim Sprechen.\nLoslassen. Dann liegt dein Text bereit.")
                    : String(
                        format: L10n.text("Halte %@ beim Sprechen.\nLoslassen. Und dein Text steht da."),
                        key.name)
            )
            .foregroundStyle(.secondary).lineSpacing(5)
            HStack(spacing: 22) {
                Button {
                } label: {
                    VStack(spacing: 2) {
                        Text(verbatim: MacEnvironment.isSandboxed ? "⌃⌥" : key.symbol)
                            .font(.system(size: 33)).lineLimit(1).minimumScaleFactor(0.4)
                        if MacEnvironment.isSandboxed {
                            Text(L10n.text("Leertaste")).font(.caption)
                        } else if let side = key.side {
                            Text(L10n.text(side)).font(.caption)
                        }
                    }.frame(width: 78, height: 78)
                }.buttonStyle(
                    PracticeKeyStyle(onPress: { dictation.startPractice() }, onRelease: { dictation.finish() })
                )
                .disabled(!dictation.microphoneReady || dictation.busy)
                .accessibilityLabel(L10n.text("Zum Ausprobieren gedrückt halten"))
                .accessibilityAction {
                    // Holding is not possible with VoiceOver, so its action starts and stops instead.
                    if dictation.recording { dictation.finish() } else { dictation.startPractice() }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("Halten. Sprechen. Loslassen.")).font(.headline)
                    Text(
                        L10n.text(
                            MacEnvironment.isSandboxed
                                ? "Füge deinen Text danach mit ⌘V ein." : "Flype schreibt dort, wo dein Cursor steht.")
                    ).font(.subheadline).foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(FlypeDesign.soft, in: RoundedRectangle(cornerRadius: 22))
            if !ready {
                Button(L10n.text("Einrichtung fortsetzen")) { selection = "setup" }.buttonStyle(.borderedProminent)
            }
            if dictation.recording || dictation.busy {
                HStack {
                    if dictation.busy { ProgressView().controlSize(.small) }
                    Text(L10n.text(dictation.status)).font(.subheadline)
                    Spacer()
                    Button(L10n.text("Abbrechen")) { dictation.cancel() }.disabled(!dictation.canCancel)
                }
            } else if !dictation.result.isEmpty || practice {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Dein Text")).font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $dictation.result).font(.body).frame(minHeight: 110).padding(12)
                        .scrollContentBackground(.hidden).background(
                            FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 14))
                    Text(L10n.text(dictation.status)).font(.footnote).foregroundStyle(.secondary)
                    if let notice = dictation.cleanupNotice {
                        Text(L10n.text(notice)).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !dictation.original.isEmpty {
                        DisclosureGroup(L10n.text("Original vergleichen")) {
                            Text(dictation.original).textSelection(.enabled)
                            Button(L10n.text("Original übernehmen")) { dictation.useOriginal() }
                        }
                    }
                    if !dictation.result.isEmpty {
                        Button(L10n.text("Text kopieren")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dictation.result, forType: .string)
                        }
                    }
                }
            } else {
                Button(L10n.text("In Ruhe ausprobieren"), systemImage: "arrow.up.right") { practice = true }
                    .buttonStyle(.plain).foregroundStyle(FlypeDesign.accent)
            }
            VStack(spacing: 0) {
                Button {
                    selection = "settings"
                } label: {
                    FlypeRow(
                        title: "Dein Schreibstil", symbol: "sparkles",
                        detail: (DictationMode(rawValue: mode) ?? .cleaned).title)
                }.buttonStyle(.plain)
                Divider()
                Button {
                    selection = "words"
                } label: {
                    FlypeRow(title: "Deine Wörter", symbol: "book")
                }.buttonStyle(.plain)
            }
            FlypePrivacyNote()
        }.navigationTitle(L10n.text("Start"))
    }
    private var setup: some View {
        Form {
            Section {
                Text(
                    L10n.text(
                        dictation.microphoneReady
                            ? "Aufnahmen werden auf deinem Gerät verarbeitet."
                            : "Erlaube Flype den Mikrofonzugriff. Aufgenommen wird nur, wenn du die Mikrofontaste hältst."
                    ))
                if dictation.microphoneReady {
                    Label(L10n.text("Mikrofon ist bereit"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(FlypeDesign.accent)
                } else {
                    Button(L10n.text("Mikrofon erlauben")) { dictation.requestMicrophone() }
                }
            } header: {
                Text(L10n.text("1 · ") + L10n.text("Mikrofon"))
            }
            if !MacEnvironment.isSandboxed {
                Section {
                    Text(
                        L10n.text(
                            dictation.accessibilityReady
                                ? "Flype schreibt dort, wo dein Cursor steht."
                                : "Erlaube Bedienungshilfen, damit Flype deine Mikrofontaste erkennt und deinen Text einfügt."
                        ))
                    if dictation.accessibilityReady {
                        Label(L10n.text("Bedienungshilfen sind erlaubt"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(FlypeDesign.accent)
                    } else {
                        Button(L10n.text("Bedienungshilfen öffnen")) { dictation.requestAccessibility() }
                    }
                } header: {
                    Text(L10n.text("2 · ") + L10n.text("Text einfügen"))
                }
            }
            Section {
                Text(
                    MacEnvironment.isSandboxed
                        ? L10n.text(
                            "Öffne ein Textfeld in einer anderen App. Halte ⌃⌥ Leertaste, sprich einen Satz, lass los und füge den Text mit ⌘V ein."
                        )
                        : String(
                            format: L10n.text(
                                "Öffne ein Textfeld in einer anderen App. Halte %@, sprich einen Satz und lass los."),
                            key.name))
                Text(
                    L10n.text(
                        "Tastenkürzel wie ⌘C funktionieren wie gewohnt. Ein kurzes Antippen startet keine Transkription."
                    )
                )
                .font(.footnote).foregroundStyle(.secondary)
                Button(L10n.text("Berechtigungen erneut prüfen")) { dictation.refreshPermissions() }
                if ready {
                    Button(L10n.text("Ausprobieren")) {
                        selection = "home"
                        practice = true
                    }.buttonStyle(.borderedProminent)
                }
                if dictation.accessibilityReady && !dictation.shortcutReady {
                    Text(L10n.text("Öffne Flype nach der Freigabe neu, falls nötig."))
                }
            } header: {
                Text(L10n.text(MacEnvironment.isSandboxed ? "2 · " : "3 · ") + L10n.text("Deine ersten Worte."))
            }
            FlypeLanguageSettings(locked: dictation.recording || dictation.busy)
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(FlypeDesign.paper)
            .navigationTitle(L10n.text("Einrichtung & Hilfe"))
    }
    private var settings: some View {
        Form {
            Section(L10n.text("Dein Schreibstil")) {
                Picker(L10n.text("Transkriptionen"), selection: $mode) {
                    Text(L10n.text("Wörtlich")).tag("verbatim")
                    Text(L10n.text("Bereinigt")).tag("cleaned")
                }.pickerStyle(.segmented).disabled(dictation.recording || dictation.busy)
                if mode == DictationMode.cleaned.rawValue {
                    Text(
                        L10n.text("Setzt Satzzeichen und lässt Füllwörter weg.")
                    ).font(.caption).foregroundStyle(.secondary)
                }
                if !(cloudConsent && account.session != nil),
                    let explanation = TextCleanupService.availabilityMessage()
                {
                    Text(L10n.text(explanation)).font(.caption).foregroundStyle(.secondary)
                }
                if mode == DictationMode.cleaned.rawValue {
                    CloudCleanupToggle(account: account).disabled(dictation.recording || dictation.busy)
                }
            }
            if !MacEnvironment.isSandboxed {
                Section(L10n.text("Mikrofontaste")) {
                    LabeledContent(L10n.text("Mikrofontaste")) {
                        DictationKeyRecorder(keyCode: $dictationKey) { dictation.pauseShortcut($0) }
                            .disabled(dictation.recording || dictation.busy)
                    }
                    Text(L10n.text("Klicke ins Feld und drücke die gewünschte Taste. Mit Esc brichst du ab."))
                        .font(.caption).foregroundStyle(.secondary)
                    if key.typesText {
                        Text(
                            L10n.text(
                                "Diese Taste schreibt nichts mehr, solange Flype läuft. Mit ⌘, ⌥, ⌃ oder ⇧ zusammen funktioniert sie weiter."
                            )
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L10n.text("Gilt auf deinen Macs, wenn du angemeldet bist."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            FlypeLanguageSettings(locked: dictation.recording || dictation.busy)
            Section(L10n.text("Für dich")) {
                Button(L10n.text("Dein Konto")) { selection = "account" }
                Button(L10n.text("Einrichtung & Hilfe")) { selection = "setup" }
                Button(L10n.text("Deine Privatsphäre")) { selection = "privacy" }
            }
            Section {
                DisclosureGroup(L10n.text("Weitere Einstellungen")) {
                    Picker(L10n.text("Spracherkennung"), selection: $provider) {
                        if speechSetup.appleAvailable || provider == "apple" {
                            Text(L10n.text("Apple")).tag("apple")
                        }
                        if speechSetup.parakeetInstalled || provider == "parakeet" {
                            Text(L10n.text("Parakeet")).tag("parakeet")
                        }
                    }
                    .disabled(dictation.recording || dictation.busy)
                    if !speechSetup.parakeetInstalled {
                        Text(L10n.text("Download: 632 MB")).font(.caption).foregroundStyle(.secondary)
                    }
                    Label(
                        L10n.text(
                            speechSetup.parakeetInstalled
                                ? "Parakeet ist geladen" : "Parakeet ist noch nicht geladen"),
                        systemImage: speechSetup.parakeetInstalled ? "checkmark.circle" : "arrow.down.circle")
                    if let progress = speechSetup.progress {
                        ProgressView(value: progress)
                            .accessibilityLabel(L10n.text("Parakeet herunterladen"))
                        Button(L10n.text("Download abbrechen")) { speechSetup.cancelDownload() }
                    } else if !speechSetup.parakeetInstalled {
                        Button(L10n.text("Parakeet herunterladen")) { speechSetup.download() }
                            .disabled(dictation.busy || dictation.recording)
                    } else if speechSetup.appleAvailable {
                        Button(L10n.text("Modell löschen"), role: .destructive) { confirmingModelDelete = true }
                            .disabled(dictation.busy || dictation.recording)
                    }
                    if let message = speechSetup.message {
                        Text(L10n.text(message)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(L10n.text("Privatsphäre")) {
                Text(
                    L10n.text(
                        "Deine Wörter und Einstellungen werden synchronisiert. Aufnahmen bleiben auf deinem Gerät."
                    )
                )
            }
        }.formStyle(.grouped).scrollContentBackground(.hidden).background(FlypeDesign.paper).navigationTitle(
            L10n.text("Einstellungen")
        )
        .task { await speechSetup.refresh() }
        .confirmationDialog(
            L10n.text("Modell löschen?"), isPresented: $confirmingModelDelete, titleVisibility: .visible
        ) {
            Button(L10n.text("Modell löschen"), role: .destructive) { Task { await speechSetup.deleteModel() } }
            Button(L10n.text("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L10n.text("Flype verwendet dann die Apple-Spracherkennung. Du kannst Parakeet später erneut laden."))
        }
    }
}

private struct PracticeKeyStyle: ButtonStyle {
    let onPress: () -> Void
    let onRelease: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(
                RoundedRectangle(cornerRadius: 17).stroke(
                    FlypeDesign.accent.opacity(configuration.isPressed ? 0.6 : 0.08),
                    lineWidth: configuration.isPressed ? 3 : 1)
            )
            .offset(y: configuration.isPressed ? 1 : 0)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { onPress() } else { onRelease() } }
    }
}
