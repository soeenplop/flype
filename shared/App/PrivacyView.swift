import FlypeCore
import SwiftUI

struct PrivacyView: View {
    @State private var notice: String?
    @State private var hasPendingText = false
    var body: some View {
        FlypePage {
            Image(systemName: "lock.shield").font(.system(size: 36, weight: .light)).foregroundStyle(FlypeDesign.accent)
                .accessibilityHidden(true)
            Text(L10n.text("Deine Worte bleiben deine.")).font(.largeTitle.weight(.semibold).leading(.tight))
                .accessibilityAddTraits(.isHeader)
            item(
                "Cloud nur auf deinen Wunsch",
                "Aufnahmen bleiben immer auf deinem Gerät. Text verlässt es nur, wenn du „Bereinigt“ wählst."
            )
            item(
                "Cloud-Bereinigung",
                "Wählst du „Bereinigt“, geht jede Transkription mit bis zu 200 Zeichen vor und nach dem Cursor und passenden Begriffen aus deinen Wörtern über Supabase an OpenAI und wird dort von einem KI-Modell verarbeitet. Flype speichert den Text nicht, nur die Anzahl deiner Anfragen und Zeichen für das Nutzungslimit."
            )
            item(
                "Mikrofon",
                "Flype nimmt nur nach deinem Start auf und zeigt das deutlich an. Aufnahmen werden nach der Verarbeitung oder beim Abbrechen gelöscht."
            )
            item(
                "Kein Transkriptionsverlauf",
                "Dein letzter Text bleibt nur im Arbeitsspeicher, bis du ihn löschst, neu aufnimmst oder Flype beendet wird."
            )
            item(
                "Sprachmodell",
                "Wenn du Parakeet lädst, ruft Flype das Modell von Hugging Face ab. Dabei wird nur deine IP-Adresse übertragen, keine Aufnahmen oder Texte."
            )
            item(
                "Konto und Synchronisierung",
                "Ein Konto ist freiwillig. Damit speichert Flype deine E-Mail-Adresse, Nutzerkennung, Wörter und Einstellungen bei unserem Dienstleister Supabase, damit sie auf deinen Geräten verfügbar sind. Du meldest dich über Apple oder Google an. Deine Anmeldung wird geschützt im Schlüsselbund gespeichert."
            )
            item(
                "Löschen",
                "Unter „Dein Konto“ kannst du dein Konto samt synchronisierter Daten endgültig löschen. Lokale Wörter und Einstellungen bleiben auf diesem Gerät."
            )
            #if os(macOS)
                item(
                    "Lokale Daten auf dem Mac",
                    "Wenn du Flype in den Papierkorb legst, bleiben lokale Wörter, Einstellungen, Sprachmodelle und die Anmeldung auf deinem Mac erhalten. Melde dich vor dem Entfernen in Flype ab."
                )
            #else
                item(
                    "Lokale Daten",
                    "Beim Löschen der App entfernt iOS ihre lokalen Dateien. Eine Anmeldung im Schlüsselbund kann erhalten bleiben. Melde dich vor dem Löschen in Flype ab."
                )
            #endif
            item(
                "Keine Werbung und kein Tracking",
                "Flype zeigt keine Werbung, erstellt keine Profile und gibt deine Daten nicht an Werbepartner weiter.")
            #if os(iOS)
                item(
                    "Keine Aufzeichnung beim Tippen",
                    "Flype speichert deine Eingaben nicht. Nur beim Start einer Transkription liest Flype bis zu 200 Zeichen vor und nach dem Cursor, damit der Text zum Satz passt. Sie werden danach gelöscht und gehen nur bei „Bereinigt“ an einen Server."
                )
                item(
                    "Automatisches Einfügen",
                    "Der Text wird kurzzeitig mit deiner Tastatur geteilt und nach dem Einfügen gelöscht. Nicht eingefügter Text verfällt nach zehn Minuten."
                )
                if hasPendingText {
                    Button(L10n.text("Ausstehenden Text löschen"), role: .destructive) {
                        do {
                            try ResultStore.shared().clear()
                            hasPendingText = false
                            notice = "Der ausstehende Text wurde gelöscht."
                        } catch { notice = "Der ausstehende Text konnte nicht gelöscht werden." }
                    }.buttonStyle(.bordered)
                }
                if let notice { Text(L10n.text(notice)).font(.subheadline) }
                Text(
                    L10n.text(
                        "Nach dem ersten Start bleibt das Mikrofon für weitere Transkriptionen bereit, ohne dass zwischen den Transkriptionen Audio gespeichert wird. Das endet, wenn du es in Flype ausschaltest, dein Gerät sperrst oder die Flype-Tastatur fünf Minuten nicht nutzt."
                    )
                )
                .font(.footnote).foregroundStyle(.secondary)
            #endif
            Link(L10n.text("Vollständige Datenschutzerklärung"), destination: FlypeLinks.privacyPolicy())
            Link(L10n.text("Hilfe und Kontakt"), destination: FlypeLinks.support())
        }.navigationTitle(L10n.text("Deine Privatsphäre"))
            #if os(iOS)
                .task { hasPendingText = (try? ResultStore.shared().pending()) != nil }
            #endif
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
    }
    private func item(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.text(title)).font(.headline)
            Text(L10n.text(description)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
