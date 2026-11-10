import FlypeCore
import SwiftUI

#if os(iOS)
    import StoreKit
#endif

/// Flype Pro in the account page. The Mac sells it through Stripe in the browser, iPhone and iPad through
/// the App Store; the server reports what is active, whichever platform it was bought on.
struct SubscriptionView: View {
    @ObservedObject var account: AccountController
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
                if status.isPro {
                    if let period = status.period {
                        Text(L10n.text(period == .year ? "Jahresabo" : "Monatsabo")).foregroundStyle(.secondary)
                    }
                    if let line = stateLine(status) { Text(line).foregroundStyle(.secondary) }
                }
                #if os(macOS)
                    StripeSubscriptionControls(account: account, status: status)
                #else
                    AppStoreSubscriptionControls(account: account, store: account.appStore, status: status)
                #endif
            }
        }
    }

    private func stateLine(_ status: FlypeCore.SubscriptionStatus) -> String? {
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

#if os(macOS)
    private struct StripeSubscriptionControls: View {
        @ObservedObject var account: AccountController
        let status: FlypeCore.SubscriptionStatus
        @State private var period = BillingPeriod.year
        private var locale: Locale { Locale(identifier: FlypeLanguage.interface().localeIdentifier) }
        var body: some View {
            if status.isPro {
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
            } else {
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
        }

        private func priceLine(trial: Bool) -> String {
            let price = period.price.formatted(.currency(code: "EUR").locale(locale))
            if trial { return String(format: L10n.text("7 Tage gratis, danach %@ pro Jahr"), price) }
            return String(format: L10n.text(period == .year ? "%@ pro Jahr" : "%@ pro Monat"), price)
        }
    }
#else
    /// No link leads to the Stripe checkout here: on iPhone and iPad, Pro is sold through the App Store only.
    private struct AppStoreSubscriptionControls: View {
        @ObservedObject var account: AccountController
        @ObservedObject var store: AppStoreSubscriptions
        let status: FlypeCore.SubscriptionStatus
        @State private var showingStore = false
        @State private var managing = false
        var body: some View {
            VStack(alignment: .leading, spacing: 16) { controls }
                .manageSubscriptionsSheet(isPresented: $managing)
                .sheet(isPresented: $showingStore) { SubscriptionStore(store: store) }
        }
        @ViewBuilder private var controls: some View {
            if status.isPro {
                switch status.source {
                case .appStore:
                    Button(L10n.text("Abo verwalten")) { managing = true }
                case .direct:
                    Text(L10n.text("Über Stripe abgeschlossen. Verwalte es in Flype auf deinem Mac."))
                        .font(.footnote).foregroundStyle(.secondary)
                case .manual, nil:
                    EmptyView()
                }
            } else {
                Text(L10n.text("Bereinige ohne Wochenlimit, auf all deinen Geräten.")).foregroundStyle(.secondary)
                Button(L10n.text("Flype Pro ansehen")) { showingStore = true }.buttonStyle(.borderedProminent)
                HStack(spacing: 10) {
                    Button(L10n.text("Käufe wiederherstellen")) { Task { await store.restore() } }
                        .disabled(store.restoring)
                    if store.restoring { ProgressView().controlSize(.small) }
                }
            }
            if let message = store.message {
                Text(L10n.text(message)).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private struct SubscriptionStore: View {
        @ObservedObject var store: AppStoreSubscriptions
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            SubscriptionStoreView(productIDs: AppStoreSubscriptions.productIDs) {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 40, weight: .light))
                        .foregroundStyle(FlypeDesign.accent)
                    Text(verbatim: "Flype Pro").font(.largeTitle.weight(.semibold))
                    Text(L10n.text("Bereinige ohne Wochenlimit, auf all deinen Geräten."))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding()
            }
            .subscriptionStorePolicyDestination(url: FlypeLinks.privacyPolicy(), for: .privacyPolicy)
            .subscriptionStorePolicyDestination(url: FlypeLinks.appleStandardEULA, for: .termsOfService)
            .storeButton(.visible, for: .cancellation)
            .inAppPurchaseOptions { _ in
                guard let token = store.appAccountToken else { return [] }
                return [.appAccountToken(token)]
            }
            .onInAppPurchaseCompletion { _, result in
                if case .success(let purchase) = result {
                    await store.purchased(purchase)
                    if case .success = purchase { dismiss() }
                }
            }
            .tint(FlypeDesign.accent)
        }
    }
#endif
