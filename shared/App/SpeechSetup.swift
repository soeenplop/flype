import FlypeCore
import SwiftUI

/// Owns the recognizer choice and the Parakeet download for the setup screen and the settings.
@MainActor
final class SpeechSetupController: ObservableObject {
    @Published private(set) var requirement = SpeechSetupPolicy.Requirement.checking
    @Published private(set) var parakeetInstalled = false
    @Published private(set) var appleAvailable = false
    @Published private(set) var progress: Double?
    @Published private(set) var message: String?
    private var resumePolicy = DownloadResumePolicy()
    private var downloadTask: Task<Void, Never>?

    var downloading: Bool { progress != nil }

    func refresh() async {
        guard !downloading else { return }
        let installed = await ParakeetModelStore.shared.isInstalled()
        let apple = await AppleSpeechEngine.isAvailable(language: .recognition())
        guard !downloading else { return }
        parakeetInstalled = installed
        appleAvailable = apple
        requirement = SpeechSetupPolicy.requirement(
            provider: DictationOptions.current().provider, parakeetInstalled: installed, appleAvailable: apple)
        // The app ended during a download, and the system may have continued it. Show that and finish it.
        let pending = await ParakeetModelStore.shared.isDownloadPending()
        if resumePolicy.consume(pending: pending) { download() }
    }

    func download() {
        guard !downloading else { return }
        resumePolicy.beganDownload()
        progress = 0
        message = nil
        downloadTask = Task {
            do {
                try await ParakeetModelStore.shared.install { value in
                    Task { @MainActor in
                        // Network callbacks are far more frequent than the view can show.
                        guard let shown = self.progress, value - shown >= 0.002 || value >= 1 else { return }
                        self.progress = value
                    }
                }
                UserDefaults.standard.set(SpeechProvider.parakeet.rawValue, forKey: "speechProvider")
            } catch  where Task.isCancelled {
                // URLSession reports a cancelled download as its own error instead of CancellationError.
                message = "Abgebrochen. Du kannst den Download jederzeit neu starten."
            } catch ParakeetModelStore.Failure.insufficientSpace {
                message = ParakeetModelStore.Failure.insufficientSpace.localizedDescription
            } catch {
                message =
                    "Der Download konnte nicht abgeschlossen werden. Prüfe deine Internetverbindung und versuche es erneut."
            }
            progress = nil
            downloadTask = nil
            await refresh()
        }
    }

    func cancelDownload() { downloadTask?.cancel() }

    func useApple() {
        UserDefaults.standard.set(SpeechProvider.apple.rawValue, forKey: "speechProvider")
        Task { await refresh() }
    }

    /// Only offered while Apple recognition can take over.
    func deleteModel() async {
        do {
            try await ParakeetSpeechEngine.unload()
            try await ParakeetModelStore.shared.delete()
            UserDefaults.standard.set(SpeechProvider.apple.rawValue, forKey: "speechProvider")
            message = "Modell gelöscht."
        } catch { message = error.localizedDescription }
        await refresh()
    }

}

/// Shown on first start and whenever a device has no usable recognizer. There is no way past it
/// without a recognizer, because dictation cannot work otherwise.
struct SpeechSetupView: View {
    @ObservedObject var setup: SpeechSetupController
    @State private var showingPrivacy = false

    var body: some View {
        FlypePage {
            FlypeBrand()
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    L10n.text(
                        setup.requirement == .choice ? "Wähle deine Spracherkennung." : "Spracherkennung laden")
                )
                .font(.largeTitle.weight(.semibold).leading(.tight)).accessibilityAddTraits(.isHeader)
                Text(
                    L10n.text(
                        setup.requirement == .choice
                            ? "Beide arbeiten lokal auf deinem Gerät. Du kannst das später in den Einstellungen ändern."
                            : "Für Transkriptionen braucht Flype einmalig das Sprachmodell Parakeet. Ohne dieses Modell ist auf diesem Gerät keine Transkription möglich."
                    )
                )
                .foregroundStyle(.secondary)
            }
            FlypeCard {
                Label {
                    Text(verbatim: "Parakeet").font(.headline)
                } icon: {
                    Image(systemName: "waveform").foregroundStyle(FlypeDesign.accent)
                }
                Text(L10n.text("Empfohlen. Erkennt mehrere Sprachen und bleibt auf diesem Gerät."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(L10n.text("Wir empfehlen WLAN. Du kannst Flype währenddessen verlassen."))
                    .font(.footnote).foregroundStyle(.secondary)
                if let progress = setup.progress {
                    ProgressView(value: progress) {
                        Text(verbatim: progress.formatted(.percent.precision(.fractionLength(0)))).font(.footnote)
                    }
                    .tint(FlypeDesign.accent)
                    Button(L10n.text("Download abbrechen"), role: .cancel) { setup.cancelDownload() }
                } else {
                    Button {
                        setup.download()
                    } label: {
                        Text(L10n.text("Parakeet herunterladen (632 MB)")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FlypePrimaryButtonStyle())
                }
            }
            if setup.requirement == .choice {
                FlypeCard {
                    Label {
                        Text(L10n.text("Apple-Spracherkennung")).font(.headline)
                    } icon: {
                        Image(systemName: "apple.logo")
                    }
                    Text(
                        L10n.text(
                            "Kein Download durch Flype nötig. Fehlende Sprachdaten lädt das System bei der ersten Transkription."
                        )
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    Button(L10n.text("Apple-Spracherkennung verwenden")) { setup.useApple() }
                        .disabled(setup.downloading)
                }
            }
            if let message = setup.message {
                Text(L10n.text(message)).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Text(
                L10n.text(
                    "Das Modell stammt von NVIDIA (CC BY 4.0) und wird von Hugging Face geladen. Dabei wird nur deine IP-Adresse übertragen, keine Aufnahmen."
                )
            )
            .font(.footnote).foregroundStyle(.secondary)
            Button(L10n.text("Deine Privatsphäre")) { showingPrivacy = true }.font(.footnote).frame(minHeight: 44)
        }
        .accessibilityAddTraits(.isModal)
        .sheet(isPresented: $showingPrivacy) {
            NavigationStack {
                PrivacyView().toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Fertig")) { showingPrivacy = false }
                    }
                }
            }
            .tint(FlypeDesign.accent)
            #if os(macOS)
                .frame(minWidth: 560, minHeight: 560)
            #endif
        }
    }
}
