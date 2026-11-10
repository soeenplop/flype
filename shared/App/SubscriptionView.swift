import FlypeCore
import SwiftUI

#if os(macOS)
    /// Flype Pro in the account page. The Mac sells it through Stripe in the browser; the server reports
    /// what is active, whichever platform it was bought on.
    struct SubscriptionView: View {
        @ObservedObject var account: AccountController
        @State private var period = BillingPeriod.year
        private var locale: Locale { Locale(identifier: FlypeLanguage.interface().localeIdentifier) }
        var body: some View {
            if let status = account.subscription {
                FlypeCard {
                    Label {
                        Text(verbatim: "Flype Pro").font(.headline)
                    } icon: {
                        Image(systemName: status.isPro ? "checkmark.seal.fill" : "sparkles")
                            .foregroundStyle(FlypeDesign.accent)
                    }
                    if status.isPro { active(status) } else { offer(status) }
                }
            }
        }

        @ViewBuilder private func active(_ status: SubscriptionStatus) -> some View {
            if let period = status.period {
                Text(L10n.text(period == .year ? "Jahresabo" : "Monatsabo")).foregroundStyle(.secondary)
            }
            if let line = stateLine(status) { Text(line).foregroundStyle(.secondary) }
            switch status.source {
            case .direct:
                Button(L10n.text("Abo verwalten")) { Task { await account.openBilling(period: nil) } }
                    .disabled(account.openingBilling)
            case .appStore:
                Text(L10n.text("Über den App Store abgeschlossen. Verwalte es auf deinem iPhone oder iPad."))
                    .font(.footnote).foregroundStyle(.secondary)
            case .manual, nil:
                EmptyView()
            }
        }

        @ViewBuilder private func offer(_ status: SubscriptionStatus) -> some View {
            Text(L10n.text("Bereinige ohne Wochenlimit, auf all deinen Geräten.")).foregroundStyle(.secondary)
            Picker("", selection: $period) {
                Text(L10n.text("Jährlich")).tag(BillingPeriod.year)
                Text(L10n.text("Monatlich")).tag(BillingPeriod.month)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            let trial = period.hasTrial && status.trialAvailable
            Text(priceLine(trial: trial)).font(.body.weight(.medium))
            HStack(spacing: 10) {
                Button(L10n.text(trial ? "7 Tage gratis testen" : "Abonnieren")) {
                    Task { await account.openBilling(period: period) }
                }
                .buttonStyle(.borderedProminent).disabled(account.openingBilling)
                if account.openingBilling { ProgressView().controlSize(.small) }
            }
            Text(L10n.text("Du bezahlst über Stripe im Browser. Jederzeit kündbar."))
                .font(.footnote).foregroundStyle(.secondary)
        }

        private func priceLine(trial: Bool) -> String {
            let price = period.price.formatted(.currency(code: "EUR").locale(locale))
            if trial { return String(format: L10n.text("7 Tage gratis, danach %@ pro Jahr"), price) }
            return String(format: L10n.text(period == .year ? "%@ pro Jahr" : "%@ pro Monat"), price)
        }

        private func stateLine(_ status: SubscriptionStatus) -> String? {
            if status.state == .pastDue {
                return L10n.text("Die letzte Zahlung ist fehlgeschlagen. Bitte prüfe deine Zahlungsart.")
            }
            guard let end = status.periodEndsAt else { return nil }
            let date = end.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(locale))
            let key =
                switch (status.source, status.state, status.willRenew) {
                case (.manual, _, _): "Aktiv bis %@"
                case (_, .trialing, _): "Gratis-Test bis %@"
                case (_, _, true): "Verlängert sich am %@"
                default: "Endet am %@"
                }
            return String(format: L10n.text(key), date)
        }
    }
#endif
