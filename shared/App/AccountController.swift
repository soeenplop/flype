import AuthenticationServices
import Combine
import CryptoKit
import FlypeCore
import Foundation
import Security
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

@MainActor
final class AccountController: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var session: CloudSession?
    @Published private(set) var status = "Ohne Konto · auf diesem Gerät"
    @Published private(set) var working = false
    @Published private(set) var syncing = false
    @Published private(set) var conflict = false
    @Published private(set) var settingsConflict = false
    @Published private(set) var needsSignIn = false
    /// Deleting needs a fresh Apple sign-in. The session stays valid, so syncing continues meanwhile.
    @Published private(set) var needsDeletionSignIn = false
    @Published var message: String?
    private static weak var current: AccountController?
    private var refreshTask: Task<CloudSession, Error>?
    private let api = SupabaseAPI()
    private var browser: ASWebAuthenticationSession?
    private var epoch = UUID()
    private var timer: Task<Void, Never>?
    private var cache = AccountSyncCache()
    private var cacheReady = false
    private var subscriptions: Set<AnyCancellable> = []
    private var scheduledSync: Task<Void, Never>?
    private var syncAgain = false
    private var observedSettings = SyncedSettings.current()
    private var deletionConfirmation = AccountDeletionConfirmation()
    private var store: PersonalDictionaryStore? { try? .shared() }
    override init() {
        defer { Self.current = self }
        super.init()
        do {
            cache = try AccountSyncCache.load()
            try cache.recoverSwitch(store: store)
            session = try CredentialVault.read()
            if cache.active != session?.user.id.uuidString {
                try switchAccount(to: session?.user.id.uuidString, importGuest: false)
            }
            cacheReady = true
            if session != nil { status = "Wörter und Einstellungen werden abgeglichen …" }
        } catch { message = "Dein Konto konnte nicht geladen werden. Deine lokalen Begriffe bleiben erhalten." }
        NotificationCenter.default.publisher(for: PersonalDictionaryStore.didChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.scheduleSync() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self else { return }
                let current = SyncedSettings.current()
                guard current != self.observedSettings else { return }
                self.observedSettings = current
                self.scheduleSync()
            }.store(in: &subscriptions)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
    func signIn(provider: String, importGuest: Bool) {
        guard cacheReady, !working, !syncing else { return }
        working = true
        message = nil
        let operation = UUID()
        epoch = operation
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
            working = false
            return
        }
        let verifier = Data(random).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        #if os(macOS)
            let scheme = "flype-mac"
        #else
            let scheme = "flype"
        #endif
        let callback = scheme + "://auth/callback"
        let browser = ASWebAuthenticationSession(
            url: api.authorizationURL(provider: provider, callback: callback, challenge: challenge),
            callbackURLScheme: scheme
        ) { [weak self] url, error in
            Task { @MainActor in
                guard let self, self.epoch == operation else { return }
                defer {
                    self.working = false
                    self.browser = nil
                }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    if self.needsDeletionSignIn { self.message = Self.deletionSignInMessage }
                    return
                }
                guard let url, url.scheme == scheme, url.host == "auth", url.path == "/callback",
                    let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {
                        $0.name == "code"
                    })?.value
                else {
                    self.message = "Die Anmeldung wurde nicht abgeschlossen. Bitte versuche es erneut."
                    return
                }
                do {
                    var session = try await self.api.exchange(code: code, verifier: verifier)
                    guard self.epoch == operation else { return }
                    session.savedAt = Date()
                    // Switch journal recovers interrupted account changes without mixing dictionaries.
                    try CredentialVault.save(session)
                    self.deletionConfirmation.signedIn(
                        account: session.user.id, provider: session.user.metadata?.provider)
                    self.session = session
                    self.needsSignIn = false
                    self.needsDeletionSignIn = false
                    self.cacheReady = false
                    try self.switchAccount(to: session.user.id.uuidString, importGuest: importGuest)
                    self.cacheReady = true
                } catch { self.message = error.localizedDescription }
                self.working = false
                await self.sync()
            }
        }
        browser.presentationContextProvider = self
        browser.prefersEphemeralWebBrowserSession = true
        self.browser = browser
        if !browser.start() {
            self.browser = nil
            working = false
            message = "Das Anmeldefenster konnte nicht geöffnet werden."
        }
    }
    func signOut() async {
        guard cacheReady, !working, !syncing else { return }
        let old = session
        epoch = UUID()
        working = true
        defer { working = false }
        do {
            try CredentialVault.delete()
            session = nil
            cacheReady = false
            try switchAccount(to: nil, importGuest: false)
            cacheReady = true
            conflict = false
            settingsConflict = false
            needsSignIn = false
            needsDeletionSignIn = false
            deletionConfirmation = AccountDeletionConfirmation()
            status = "Ohne Konto · auf diesem Gerät"
            if let old { try? await api.logout(token: old.accessToken) }
        } catch { message = error.localizedDescription }
    }
    private static let deletionSignInMessage =
        "Bitte melde dich zur Bestätigung einmal erneut mit Apple an. Lösche dein Konto danach noch einmal."
    /// Removes the account with its synced data. Local dictation keeps working as a guest.
    func deleteAccount() async {
        guard cacheReady, !working, !syncing, var current = session else { return }
        let usesApple = current.user.metadata?.provider == "apple"
        if usesApple, current.appleRevocationToken == nil, !deletionConfirmation.isConfirmed(for: current.user.id) {
            deletionConfirmation.request(for: current.user.id)
            needsDeletionSignIn = true
            message = Self.deletionSignInMessage
            return
        }
        working = true
        defer { working = false }
        epoch = UUID()
        message = nil
        do {
            if current.needsRefresh {
                let providerToken = current.providerRefreshToken
                let providerAccessToken = current.providerToken
                current = try await api.refresh(token: current.refreshToken)
                current.providerRefreshToken = providerToken
                current.providerToken = providerAccessToken
                current.savedAt = Date()
                try CredentialVault.save(current)
                session = current
            }
            try await api.deleteAccount(session: current)
            try CredentialVault.delete()
            session = nil
            cacheReady = false
            let account = current.user.id.uuidString
            try switchAccount(to: nil, importGuest: false)
            cache.forget(account: account)
            try cache.save()
            cacheReady = true
            needsDeletionSignIn = false
            deletionConfirmation = AccountDeletionConfirmation()
            status = "Ohne Konto · auf diesem Gerät"
            message = "Dein Konto und deine synchronisierten Daten wurden gelöscht."
        } catch { message = error.localizedDescription }
    }
    private func scheduleSync() {
        if syncing {
            syncAgain = true
            return
        }
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            self?.scheduledSync = nil
            await self?.sync()
        }
    }
    private func finishSyncing() {
        syncing = false
        if syncAgain {
            syncAgain = false
            scheduleSync()
        }
    }
    /// A refresh token works only once, so syncing and cloud cleanup share one request.
    private func refreshedSession(_ old: CloudSession) async throws -> CloudSession {
        if let refreshTask { return try await refreshTask.value }
        let operation = epoch
        let task = Task { [api] in
            var fresh = try await api.refresh(token: old.refreshToken)
            guard epoch == operation else { throw CancellationError() }
            fresh.savedAt = Date()
            fresh.providerRefreshToken = old.providerRefreshToken
            fresh.providerToken = old.providerToken
            try CredentialVault.save(fresh)
            session = fresh
            return fresh
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
    /// Cleanup needs "Bereinigt", the consent on this device and an account; otherwise the text stays verbatim.
    static func cleanupActive(mode: DictationMode) -> Bool {
        mode == .cleaned && CloudCleanup.isEnabled() && current?.session != nil
    }
    /// Runs while someone is still speaking: renews an expiring session and opens the connection to the
    /// cleanup function, so neither waits until after the recording. Sends no text.
    static func prepareCleanup(mode: DictationMode) {
        guard cleanupActive(mode: mode) else { return }
        Task {
            _ = try? await cloudCleanupToken()
            await SupabaseAPI().warmCleanup()
        }
    }
    /// Returns nil when nothing may be sent: no consent, or nobody signed in.
    static func cloudCleanupToken() async throws -> String? {
        guard CloudCleanup.isEnabled(), let account = current, var session = account.session else { return nil }
        guard !account.needsSignIn else { throw SupabaseAPI.Failure.sessionExpired }
        if session.needsRefresh {
            do {
                session = try await account.refreshedSession(session)
            } catch SupabaseAPI.Failure.sessionExpired {
                account.needsSignIn = true
                account.status = SupabaseAPI.Failure.sessionExpired.localizedDescription
                throw SupabaseAPI.Failure.sessionExpired
            }
        }
        return session.accessToken
    }
    func sync() async {
        guard cacheReady, !syncing, !working, !needsSignIn, var current = session,
            cache.active == current.user.id.uuidString, let store
        else { return }
        syncing = true
        let operation = epoch
        defer { finishSyncing() }
        do {
            if current.needsRefresh {
                current = try await refreshedSession(current)
                guard epoch == operation else { return }
            }
        } catch is CancellationError {
            return
        } catch SupabaseAPI.Failure.sessionExpired {
            needsSignIn = true
            status = SupabaseAPI.Failure.sessionExpired.localizedDescription
            return
        } catch {
            status = error.localizedDescription
            return
        }
        var problem: String?
        var wordsCurrent = false
        var settingsCurrent = false
        do {
            wordsCurrent = try await syncDictionary(session: current, store: store, operation: operation)
            conflict = false
        } catch is DictionaryMerge.Conflict {
            conflict = true
        } catch { problem = error.localizedDescription }
        guard epoch == operation else { return }
        do {
            settingsCurrent = try await syncSettings(session: current, operation: operation)
            settingsConflict = false
        } catch is SettingsMerge.Conflict {
            settingsConflict = true
        } catch { problem = error.localizedDescription }
        guard epoch == operation else { return }
        if conflict {
            status = "Ein Begriff wurde auf beiden Geräten geändert."
        } else if settingsConflict {
            status = "Eine Einstellung wurde auf beiden Geräten geändert."
        } else if let problem {
            status = problem
        } else if wordsCurrent && settingsCurrent {
            status = "Auf allen Geräten aktuell"
        } else {
            status = "Deine Änderungen werden gleich erneut abgeglichen."
        }
    }

    private func syncDictionary(session: CloudSession, store: PersonalDictionaryStore, operation: UUID) async throws
        -> Bool
    {
        let account = session.user.id.uuidString
        for _ in 0..<3 {
            let local = try store.snapshot()
            let base = cache.bases[account] ?? []
            let remote = try await api.readDictionary(token: session.accessToken)
            guard epoch == operation else { return false }
            let merged = try DictionaryMerge.merge(base: base, local: local.entries, remote: remote.entries)
            let accepted =
                merged.sortedEntries == remote.entries.sortedEntries
                ? remote
                : try await api.writeDictionary(token: session.accessToken, revision: remote.revision, entries: merged)
            guard epoch == operation else { return false }
            if accepted.applied == false { continue }
            let newest = try store.snapshot()
            let rebased = try DictionaryMerge.merge(
                base: local.entries, local: newest.entries, remote: accepted.entries)
            if rebased.sortedEntries != newest.entries.sortedEntries {
                try store.replace(entries: rebased, expectedRevision: newest.revision)
            }
            cache.bases[account] = accepted.entries
            try cache.save()
            return true
        }
        return false
    }

    private func syncSettings(session: CloudSession, operation: UUID) async throws -> Bool {
        let account = session.user.id.uuidString
        for _ in 0..<3 {
            let local = SyncedSettings.current()
            let remote = try await api.readSettings(token: session.accessToken)
            guard epoch == operation else { return false }
            let merged = try SettingsMerge.merge(
                base: cache.settingsBases[account], local: local, remote: remote.settings)
            let accepted =
                merged == remote.settings
                ? remote
                : try await api.writeSettings(token: session.accessToken, revision: remote.revision, settings: merged)
            guard epoch == operation else { return false }
            if accepted.applied == false { continue }
            guard let settings = accepted.settings else { throw SupabaseAPI.Failure.unavailable }
            let rebased = try SettingsMerge.merge(base: local, local: SyncedSettings.current(), remote: settings)
            rebased.apply()
            cache.settingsBases[account] = settings
            try cache.save()
            return true
        }
        return false
    }

    func resolveSettings(useLocal: Bool) async {
        guard cacheReady, !working, !syncing, let session else { return }
        syncing = true
        let operation = epoch
        defer { finishSyncing() }
        do {
            let local = SyncedSettings.current()
            let remote = try await api.readSettings(token: session.accessToken)
            guard epoch == operation else { return }
            let archiveID = UUID().uuidString
            cache.settingsArchives["conflict-local-" + archiveID] = local
            if let settings = remote.settings { cache.settingsArchives["conflict-remote-" + archiveID] = settings }
            try cache.save()
            let accepted =
                useLocal
                ? try await api.writeSettings(token: session.accessToken, revision: remote.revision, settings: local)
                : remote
            guard epoch == operation, accepted.applied != false, let settings = accepted.settings else { return }
            // Do not overwrite an edit made while the explicit resolution was in flight.
            guard SyncedSettings.current() == local else {
                message = "Deine Änderungen werden gleich erneut abgeglichen."
                return
            }
            settings.apply()
            cache.settingsBases[session.user.id.uuidString] = settings
            try cache.save()
            settingsConflict = false
            message = nil
            status = conflict ? "Ein Begriff wurde auf beiden Geräten geändert." : "Auf allen Geräten aktuell"
        } catch { message = error.localizedDescription }
    }
    /// Explicit conflict choice keeps the losing version in the protected local archive.
    func resolve(useLocal: Bool) async {
        guard cacheReady, !working, !syncing, let session, let store else { return }
        syncing = true
        let operation = epoch
        defer { finishSyncing() }
        do {
            let local = try store.snapshot()
            let remote = try await api.readDictionary(token: session.accessToken)
            guard epoch == operation else { return }
            let archiveID = UUID().uuidString
            cache.archives["conflict-local-" + archiveID] = local.entries
            cache.archives["conflict-remote-" + archiveID] = remote.entries
            try cache.save()
            var accepted = remote
            if useLocal {
                accepted = try await api.writeDictionary(
                    token: session.accessToken, revision: remote.revision, entries: local.entries)
            }
            guard epoch == operation, accepted.applied != false else { return }
            try store.replace(entries: accepted.entries, expectedRevision: local.revision)
            cache.bases[session.user.id.uuidString] = accepted.entries
            try cache.save()
            conflict = false
            message = nil
            status =
                settingsConflict ? "Eine Einstellung wurde auf beiden Geräten geändert." : "Auf allen Geräten aktuell"
        } catch { message = error.localizedDescription }
    }
    private func switchAccount(to account: String?, importGuest: Bool) throws {
        guard let store else { throw PersonalDictionaryStore.Failure.unavailable }
        let current = try store.snapshot().entries
        let localSettings = SyncedSettings.current()
        cache.stageSwitch(
            to: account, currentEntries: current, currentSettings: localSettings, importGuest: importGuest)
        try cache.save()
        try cache.recoverSwitch(store: store)
        conflict = false
        settingsConflict = false
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
            return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
            return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(
                where: \.isKeyWindow) ?? ASPresentationAnchor()
        #endif
    }
}
extension Data {
    fileprivate var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
extension Array where Element == PersonalDictionaryEntry {
    fileprivate var sortedEntries: [Element] { sorted { $0.id.uuidString < $1.id.uuidString } }
}
private enum CredentialVault {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "one.binda.flype.account",
            kSecAttrAccount as String: "supabase-session",
        ]
    }
    static func read() throws -> CloudSession? {
        var query = query
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SupabaseAPI.Failure.unavailable }
        return try JSONDecoder().decode(CloudSession.self, from: data)
    }
    static func save(_ session: CloudSession) throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw SupabaseAPI.Failure.unavailable }
        } else if status != errSecSuccess {
            throw SupabaseAPI.Failure.unavailable
        }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SupabaseAPI.Failure.unavailable }
    }
}
