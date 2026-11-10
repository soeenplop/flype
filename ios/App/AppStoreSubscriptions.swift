import Combine
import FlypeCore
import StoreKit

/// Buys and restores Flype Pro through the App Store. Every verified transaction goes to the server, which
/// checks it with Apple and alone decides what Pro allows. A transaction finishes only after the server has
/// recorded it, so StoreKit offers an interrupted one again at the next start or sign-in.
@MainActor
final class AppStoreSubscriptions: ObservableObject {
    static let productIDs = ["one.binda.flype.pro.yearly", "one.binda.flype.pro.monthly"]
    @Published private(set) var restoring = false
    @Published var message: String?
    private weak var account: AccountController?
    private var updates: Task<Void, Never>?
    private var signedIn: AnyCancellable?

    init(account: AccountController) {
        self.account = account
        updates = Task { [weak self] in
            for await update in Transaction.updates { await self?.report(update) }
        }
        signedIn = account.$session.map { $0?.user.id }.removeDuplicates().sink { [weak self] user in
            guard user != nil else { return }
            Task { await self?.reportUnfinished() }
        }
    }

    /// The Supabase user ID goes along with every purchase, so the server can tell whose it is.
    var appAccountToken: UUID? { account?.session?.user.id }

    func purchased(_ result: Product.PurchaseResult) async {
        if case .success(let verification) = result { await report(verification) }
    }

    /// Asks the App Store for this Apple ID's purchases and reports the active ones to the server.
    func restore() async {
        guard !restoring else { return }
        restoring = true
        defer { restoring = false }
        message = nil
        do { try await AppStore.sync() } catch {
            message = "Die Käufe konnten nicht wiederhergestellt werden. Bitte versuche es später erneut."
            return
        }
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement, Self.productIDs.contains(transaction.productID)
            else { continue }
            found = true
            await report(entitlement)
        }
        if !found && message == nil { message = "Mit dieser Apple-ID gibt es kein aktives Flype Pro." }
    }

    private func reportUnfinished() async {
        for await transaction in Transaction.unfinished { await report(transaction) }
    }

    private func report(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification, Self.productIDs.contains(transaction.productID),
            let account, account.session != nil
        else { return }
        do {
            let status = try await account.api.verifyAppStorePurchase(
                token: try await account.validToken(), transactionID: transaction.id)
            account.apply(status)
            await transaction.finish()
        } catch SupabaseAPI.Failure.purchaseOwnedElsewhere {
            // Retrying cannot change the owner, so the transaction is done for this account.
            message = SupabaseAPI.Failure.purchaseOwnedElsewhere.localizedDescription
            await transaction.finish()
        } catch {
            message = "Dein Kauf wird übertragen, sobald die Verbindung klappt."
        }
    }
}
