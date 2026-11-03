import FlypeCore
import SwiftUI

/// Dictated text only leaves the device after this explicit choice, which stays on this device.
struct CloudCleanupToggle: View {
    @ObservedObject var account: AccountController
    @AppStorage(CloudCleanup.consentKey) private var consent = false
    @State private var confirming = false
    var body: some View {
        Toggle(
            L10n.text("Mit OpenAI in der Cloud bereinigen"),
            isOn: Binding(
                get: { consent && account.session != nil },
                set: { enabled in
                    if enabled { confirming = true } else { consent = false }
                })
        )
        .disabled(account.session == nil)
        .confirmationDialog(
            L10n.text("Transkriptionen an OpenAI senden?"), isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(L10n.text("Einschalten")) { consent = true }
            Button(L10n.text("Abbrechen"), role: .cancel) {}
        } message: {
            Text(
                L10n.text(
                    "Jede Transkription wird mit bis zu 200 Zeichen vor dem Cursor und passenden Begriffen aus deinen Wörtern über unseren Dienstleister Supabase an OpenAI übertragen und dort von einem KI-Modell verarbeitet. Flype speichert den Text nicht. Du kannst das jederzeit wieder ausschalten."
                ))
        }
        Text(
            L10n.text(
                account.session == nil
                    ? "Dafür brauchst du ein Flype-Konto. Ohne Anmeldung bleibt die Bereinigung auf deinem Gerät."
                    : "Deine Transkription und bis zu 200 Zeichen vor dem Cursor werden dafür an OpenAI übertragen. Aufnahmen bleiben immer auf deinem Gerät."
            )
        )
        .font(.footnote).foregroundStyle(.secondary)
    }
}
