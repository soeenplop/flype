import FlypeCore
import SwiftUI

struct ProcessingSettingsView: View {
    @ObservedObject var dictation: DictationController
    @ObservedObject var account: AccountController
    @ObservedObject var speechSetup: SpeechSetupController
    var onSetup: () -> Void
    @AppStorage("speechProvider") private var provider = SpeechProvider.parakeet.rawValue
    @State private var confirmingDelete = false
    private var locked: Bool { dictation.busy || dictation.sessionActive || speechSetup.downloading }
    private var selectableProviders: [SpeechProvider] {
        SpeechProvider.allCases.filter {
            provider == $0.rawValue || ($0 == .parakeet ? speechSetup.parakeetInstalled : speechSetup.appleAvailable)
        }
    }
    var body: some View {
        Form {
            Section(L10n.text("Dein Schreibstil")) {
                CleanupModePicker(account: account).disabled(dictation.busy)
            }
            FlypeLanguageSettings(locked: locked)
            Section(L10n.text("Für dich")) {
                NavigationLink {
                    AccountView(account: account)
                } label: {
                    Label(L10n.text("Dein Konto"), systemImage: "person.crop.circle")
                }
                Button(action: onSetup) {
                    Label {
                        Text(L10n.text("Einrichtung & Hilfe")).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label(L10n.text("Deine Privatsphäre"), systemImage: "lock.shield")
                }
            }
            Section {
                DisclosureGroup(L10n.text("Weitere Einstellungen")) {
                    Picker(L10n.text("Spracherkennung"), selection: $provider) {
                        // Menu pickers ignore a disabled option, so an unusable choice is not offered.
                        ForEach(selectableProviders, id: \.rawValue) { value in
                            Text(L10n.text(value.title)).tag(value.rawValue)
                        }
                    }.disabled(locked)
                    Text(
                        L10n.text(
                            "Parakeet ist voreingestellt und arbeitet lokal auf deinem Gerät. Die Apple-Spracherkennung steht als Alternative bereit, sofern dein Gerät sie unterstützt."
                        )
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    if provider == SpeechProvider.parakeet.rawValue && !speechSetup.parakeetInstalled {
                        Text(
                            L10n.text(
                                "Parakeet ist ausgewählt, aber auf diesem Gerät noch nicht geladen. Bis dahin nutzt Flype die Apple-Spracherkennung."
                            )
                        )
                        .font(.footnote)
                    }
                    Label(
                        L10n.text(
                            speechSetup.parakeetInstalled
                                ? "Parakeet ist geladen" : "Parakeet ist noch nicht geladen"),
                        systemImage: speechSetup.parakeetInstalled ? "checkmark.circle" : "arrow.down.circle")
                    if !speechSetup.parakeetInstalled {
                        Text(L10n.text("Download: 632 MB")).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let progress = speechSetup.progress {
                        ProgressView(value: progress)
                        Button(L10n.text("Download abbrechen"), role: .cancel) { speechSetup.cancelDownload() }
                    } else if !speechSetup.parakeetInstalled {
                        Button(L10n.text("Parakeet herunterladen"), action: speechSetup.download).disabled(locked)
                    } else if speechSetup.appleAvailable {
                        // Without Apple recognition, this model is the only way to dictate on this device.
                        Button(L10n.text("Modell löschen"), role: .destructive) { confirmingDelete = true }
                            .disabled(locked)
                    }
                    if let message = speechSetup.message { Text(L10n.text(message)).font(.footnote) }
                    DisclosureGroup(L10n.text("Lizenzen")) {
                        Link(
                            L10n.text("NVIDIA · CC BY 4.0"),
                            destination: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!)
                        Link(
                            L10n.text("FluidAudio · Apache 2.0"),
                            destination: URL(string: "https://github.com/FluidInference/FluidAudio/tree/v0.18.2")!)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(FlypeDesign.paper)
        .navigationTitle(L10n.text("Einstellungen"))
        .task { await speechSetup.refresh() }
        .confirmationDialog(
            L10n.text("Modell löschen?"), isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button(L10n.text("Modell löschen"), role: .destructive) { Task { await speechSetup.deleteModel() } }
            Button(L10n.text("Abbrechen"), role: .cancel) {}
        } message: {
            Text(L10n.text("Flype verwendet dann die Apple-Spracherkennung. Du kannst Parakeet später erneut laden."))
        }
    }
}
