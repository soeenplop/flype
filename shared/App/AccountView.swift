import FlypeCore
import SwiftUI

struct AccountView: View {
    @ObservedObject var account: AccountController
    @State private var importGuest = true
    @State private var confirmingDeletion = false
    var body: some View {
        FlypePage {
            Image(systemName: "person.2").font(.system(size: 32, weight: .light)).foregroundStyle(FlypeDesign.accent)
                .padding(20).background(FlypeDesign.soft, in: RoundedRectangle(cornerRadius: 20))
            Text(
                L10n.text(account.session == nil ? "Wörter und Einstellungen.\nAuf allen Geräten." : "Dein Flype-Konto")
            )
            .font(.title.weight(.semibold).leading(.tight))
            Text(
                L10n.text(
                    account.session == nil
                        ? "Melde dich auf deinem iPhone, iPad und Mac mit demselben Konto an."
                        : "Deine Wörter und Einstellungen begleiten dich auf deinen Geräten.")
            )
            .foregroundStyle(.secondary)
            if let session = account.session {
                FlypeCard {
                    Text(verbatim: session.user.email ?? L10n.text("Dein Flype-Konto")).font(.headline)
                    Label(
                        L10n.text(account.status),
                        systemImage: account.needsSignIn
                            ? "exclamationmark.triangle"
                            : (account.conflict || account.settingsConflict)
                                ? "exclamationmark.arrow.triangle.2.circlepath" : "icloud"
                    )
                    .foregroundStyle(.secondary)
                    if account.needsSignIn {
                        signInButtons(importGuest: false)
                    } else {
                        HStack(spacing: 10) {
                            Button(L10n.text("Jetzt abgleichen")) { Task { await account.sync() } }.disabled(
                                account.syncing)
                            if account.syncing { ProgressView().controlSize(.small) }
                        }
                        if account.needsDeletionSignIn {
                            signInButtons(importGuest: false).disabled(account.syncing)
                        }
                    }
                    if account.conflict && !account.needsSignIn {
                        Text(
                            L10n.text(
                                "Beide Versionen bleiben zur Sicherheit auf diesem Gerät gespeichert. Deine Auswahl gilt für das gesamte Wörterbuch."
                            )
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.text("Wörterbuch dieses Geräts verwenden")) {
                            Task { await account.resolve(useLocal: true) }
                        }
                        Button(L10n.text("Wörterbuch aus dem Konto verwenden")) {
                            Task { await account.resolve(useLocal: false) }
                        }
                    }
                    if account.settingsConflict && !account.needsSignIn {
                        Text(
                            L10n.text(
                                "Eine Einstellung wurde auf beiden Geräten geändert. Beide Versionen bleiben erhalten.")
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.text("Einstellungen dieses Geräts verwenden")) {
                            Task { await account.resolveSettings(useLocal: true) }
                        }.disabled(account.syncing)
                        Button(L10n.text("Einstellungen aus dem Konto verwenden")) {
                            Task { await account.resolveSettings(useLocal: false) }
                        }.disabled(account.syncing)
                    }
                    Divider()
                    Button(L10n.text("Auf diesem Gerät abmelden"), role: .destructive) {
                        Task { await account.signOut() }
                    }.disabled(account.syncing)
                    Button(L10n.text("Konto löschen"), role: .destructive) { confirmingDeletion = true }
                        .disabled(account.syncing)
                }
                #if os(macOS)
                    if !account.needsSignIn { SubscriptionView(account: account) }
                #endif
            } else {
                VStack(spacing: 12) {
                    signInButtons(importGuest: importGuest)
                    Toggle(L10n.text("Meine bisherigen Begriffe ins Konto übernehmen"), isOn: $importGuest)
                        .font(.footnote).padding(.top, 8)
                }
                Text(
                    L10n.text(
                        "Du kannst Flype ohne Konto verwenden. Wörter und Einstellungen bleiben dann auf diesem Gerät.")
                )
                .font(.footnote).foregroundStyle(.secondary)
            }
            if account.working {
                VStack(spacing: 8) {
                    ProgressView().progressViewStyle(.circular)
                    Text(L10n.text("Einen Moment …")).font(.subheadline).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if let message = account.message { Text(L10n.text(message)).font(.footnote).foregroundStyle(.secondary) }
            Divider()
            Text(
                L10n.text(
                    "Gemeinsam: Schreibstil, Sprachen, Mikrofontaste und Modellauswahl. Downloads und Berechtigungen bleiben auf jedem Gerät."
                )
            )
            .font(.footnote).foregroundStyle(.secondary)
        }.disabled(account.working).navigationTitle(L10n.text("Dein Konto"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .confirmationDialog(
                L10n.text("Konto endgültig löschen?"), isPresented: $confirmingDeletion, titleVisibility: .visible
            ) {
                Button(L10n.text("Konto löschen"), role: .destructive) { Task { await account.deleteAccount() } }
                Button(L10n.text("Abbrechen"), role: .cancel) {}
            } message: {
                Text(deletionWarning)
            }
    }
    private var deletionWarning: String {
        let warning = L10n.text(
            "Dein Konto und alle synchronisierten Wörter und Einstellungen werden unwiderruflich gelöscht.")
        guard let subscription = account.subscription, subscription.isPro else { return warning }
        switch subscription.source {
        case .direct: return warning + " " + L10n.text("Dein Abo über Stripe endet dabei sofort.")
        case .appStore:
            return warning + " "
                + L10n.text(
                    "Dein Abo im App Store läuft weiter, bis du es in den Einstellungen deines iPhone kündigst.")
        case .manual, nil: return warning
        }
    }
    @ViewBuilder private func signInButtons(importGuest: Bool) -> some View {
        Button {
            account.signIn(provider: "apple", importGuest: importGuest)
        } label: {
            Label(L10n.text("Mit Apple anmelden"), systemImage: "apple.logo").frame(maxWidth: .infinity)
        }.buttonStyle(AppleSignInButtonStyle())
        Button {
            account.signIn(provider: "google", importGuest: importGuest)
        } label: {
            Text(L10n.text("Mit Google anmelden")).frame(maxWidth: .infinity)
        }.buttonStyle(GoogleSignInButtonStyle())
    }
}

/// Follows Apple's button rules: a solid black or white surface with the logo and a matching label.
private struct AppleSignInButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 16).frame(minHeight: 48)
            .background(scheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct GoogleSignInButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 16).frame(minHeight: 48)
            .background(FlypeDesign.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.4)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
