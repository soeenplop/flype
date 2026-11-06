import FlypeCore
import SwiftUI

/// "Bereinigt" means cleanup with OpenAI, so choosing it asks before any text leaves the device.
/// The consent stays on this device, so a synced mode never starts sending text from a new device.
struct CleanupModePicker: View {
    @ObservedObject var account: AccountController
    var noteFont: Font = .footnote
    @AppStorage("dictationMode") private var mode = DictationMode.cleaned.rawValue
    @AppStorage(CloudCleanup.consentKey) private var consent = false
    @State private var confirming = false
    @State private var needsAccount = false
    private var active: Bool { mode == DictationMode.cleaned.rawValue && consent && account.session != nil }
    var body: some View {
        Picker(
            L10n.text("Transkriptionen"),
            selection: Binding(
                get: { active ? DictationMode.cleaned : .verbatim },
                set: { chosen in
                    if chosen == .verbatim {
                        mode = DictationMode.verbatim.rawValue
                        consent = false
                    } else if account.session == nil {
                        needsAccount = true
                    } else {
                        confirming = true
                    }
                })
        ) {
            ForEach(DictationMode.allCases, id: \.rawValue) { value in
                Text(L10n.text(value.title)).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .confirmationDialog(
            L10n.text("Transkriptionen an OpenAI senden?"), isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(L10n.text("Einschalten")) {
                consent = true
                mode = DictationMode.cleaned.rawValue
            }
            Button(L10n.text("Abbrechen"), role: .cancel) {}
        } message: {
            Text(
                L10n.text(
                    "Jede Transkription wird mit bis zu 200 Zeichen vor und nach dem Cursor und passenden Begriffen aus deinen Wörtern über unseren Dienstleister Supabase an OpenAI übertragen und dort von einem KI-Modell verarbeitet. Flype speichert den Text nicht. Mit „Wörtlich“ schaltest du das jederzeit wieder aus."
                ))
        }
        .alert(L10n.text("Flype-Konto nötig"), isPresented: $needsAccount) {
        } message: {
            Text(L10n.text("Für die Bereinigung brauchst du ein Flype-Konto. Melde dich zuerst an."))
        }
        if active {
            Text(L10n.text("Korrigiert Satzzeichen, Rechtschreibung und Grammatik und lässt Füllwörter weg."))
                .font(noteFont).foregroundStyle(.secondary)
            Text(
                L10n.text(
                    "Deine Transkription geht dafür mit bis zu 200 Zeichen vor und nach dem Cursor an OpenAI. Aufnahmen bleiben immer auf deinem Gerät."
                )
            )
            .font(noteFont).foregroundStyle(.secondary)
        } else {
            Text(
                L10n.text(
                    "Fügt den erkannten Text unverändert ein. „Bereinigt“ korrigiert ihn mit einem KI-Modell von OpenAI in der Cloud."
                )
            )
            .font(noteFont).foregroundStyle(.secondary)
        }
    }
}
