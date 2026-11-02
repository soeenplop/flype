import Foundation

public struct CloudSession: Codable, Sendable {
    public struct User: Codable, Sendable {
        public struct Metadata: Codable, Sendable { public let provider: String? }
        enum CodingKeys: String, CodingKey {
            case id, email
            case metadata = "app_metadata"
        }
        public let id: UUID
        public let email: String?
        public let metadata: Metadata?
    }
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case providerRefreshToken = "provider_refresh_token"
        case providerToken = "provider_token"
        case user, savedAt
    }
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Double
    public let user: User
    public var savedAt: Date? = Date()
    /// Only sign-in responses contain it. Apple requires revoking this token when deleting an account.
    public var providerRefreshToken: String?
    public var providerToken: String?
    public var appleRevocationToken: (value: String, hint: String)? {
        if let value = providerRefreshToken, !value.isEmpty { return (value, "refresh_token") }
        if let value = providerToken, !value.isEmpty { return (value, "access_token") }
        return nil
    }
    public var needsRefresh: Bool { Date().timeIntervalSince(savedAt ?? .distantPast) > expiresIn - 90 }
}
/// The opt-in stays on this device, so a new device never starts sending text on its own.
public enum CloudCleanup {
    public static let consentKey = "cloudCleanupConsent"
    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: consentKey) }
}
public struct CloudDictionary: Codable, Sendable {
    public let revision: Int
    public let entries: [PersonalDictionaryEntry]
    public let applied: Bool?
}
public struct SupabaseAPI: Sendable {
    public static let projectURL = URL(string: "https://leystmzdybimmbaruywp.supabase.co")!
    public static let publicKey = "sb_publishable_2zHoQOrrV-v1zqaDNUmbwQ_WYSF4j2V"
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public enum Failure: LocalizedError {
        case unauthorized, sessionExpired, rejected, unavailable, setupRequired, appleRevocationUnavailable
        case limitReached
        public var errorDescription: String? {
            switch self {
            case .appleRevocationUnavailable:
                "Die Apple-Verknüpfung konnte nicht aufgehoben werden. Dein Konto wurde nicht gelöscht. Bitte versuche es später erneut."
            case .limitReached:
                "Das Limit für die Cloud-Bereinigung ist gerade erreicht. Dein Originaltext ist bereit."
            case .unauthorized: "Bitte melde dich erneut an. Deine lokalen Begriffe bleiben erhalten."
            case .sessionExpired:
                "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an. Deine lokalen Begriffe bleiben erhalten."
            case .rejected:
                "Der Server hat die Anfrage abgelehnt. Deine Begriffe bleiben auf diesem Gerät verfügbar."
            case .unavailable:
                "Die Verbindung ist gerade nicht möglich. Deine Begriffe bleiben auf diesem Gerät verfügbar."
            case .setupRequired:
                "Die Anmeldung oder Synchronisierung wird noch eingerichtet. Bitte versuche es später erneut."
            }
        }
    }
    public func authorizationURL(provider: String, callback: String, challenge: String) -> URL {
        var url = URLComponents(
            url: Self.projectURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [
            URLQueryItem(name: "provider", value: provider), URLQueryItem(name: "redirect_to", value: callback),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ]
        return url.url!
    }
    public func exchange(code: String, verifier: String) async throws -> CloudSession {
        try await request(path: "auth/v1/token?grant_type=pkce", body: ["auth_code": code, "code_verifier": verifier])
    }
    public func refresh(token: String) async throws -> CloudSession {
        do {
            return try await request(path: "auth/v1/token?grant_type=refresh_token", body: ["refresh_token": token])
        } catch Failure.rejected, Failure.unauthorized {
            // A revoked or already used refresh token cannot succeed on a later attempt.
            throw Failure.sessionExpired
        }
    }
    public func logout(token: String) async throws {
        let _: Empty = try await request(path: "auth/v1/logout?scope=local", token: token, body: [:])
    }
    public func deleteAccount(token: String) async throws {
        struct Result: Decodable { let deleted: Bool }
        let result: Result = try await request(path: "rest/v1/rpc/flype_delete_account", token: token, body: [:])
        guard result.deleted else { throw Failure.rejected }
    }
    /// Never discard the account (and its only revocation credentials) after a failed Apple request.
    public func deleteAccount(session: CloudSession) async throws {
        if session.user.metadata?.provider == "apple" {
            guard let credential = session.appleRevocationToken else { throw Failure.appleRevocationUnavailable }
            do {
                let _: Empty = try await request(
                    path: "functions/v1/revoke-apple-token", token: session.accessToken,
                    body: ["provider_token": credential.value, "token_type_hint": credential.hint])
            } catch { throw Failure.appleRevocationUnavailable }
        }
        try await deleteAccount(token: session.accessToken)
    }
    public func readDictionary(token: String) async throws -> CloudDictionary {
        try await request(path: "rest/v1/rpc/flype_read_dictionary", token: token, body: [:])
    }
    public func writeDictionary(token: String, revision: Int, entries: [PersonalDictionaryEntry]) async throws
        -> CloudDictionary
    {
        struct Write: Encodable {
            enum CodingKeys: String, CodingKey {
                case expectedRevision = "expected_revision"
                case entries = "p_entries"
            }
            let expectedRevision: Int
            let entries: [PersonalDictionaryEntry]
        }
        return try await send(
            path: "rest/v1/rpc/flype_write_dictionary", token: token,
            data: JSONEncoder().encode(Write(expectedRevision: revision, entries: entries)))
    }
    public func readSettings(token: String) async throws -> CloudSettings {
        try await request(path: "rest/v1/rpc/flype_read_settings", token: token, body: [:])
    }
    public func writeSettings(token: String, revision: Int, settings: SyncedSettings) async throws -> CloudSettings {
        struct Write: Encodable {
            enum CodingKeys: String, CodingKey {
                case expectedRevision = "expected_revision"
                case settings = "p_settings"
            }
            let expectedRevision: Int
            let settings: SyncedSettings
        }
        return try await send(
            path: "rest/v1/rpc/flype_write_settings", token: token,
            data: JSONEncoder().encode(Write(expectedRevision: revision, settings: settings)))
    }
    public func cleanDictation(
        token: String, text: String, terms: [String], language: FlypeLanguage, context: String? = nil
    ) async throws -> String {
        struct Request: Encodable {
            let text: String
            let terms: [String]
            let language: String
            let context: String?
        }
        struct Result: Decodable { let text: String }
        let result: Result = try await send(
            path: "functions/v1/cloud-cleanup", token: token,
            data: JSONEncoder().encode(
                Request(text: text, terms: terms, language: language.rawValue, context: context)),
            // Leaves time for the model on this device when the server does not answer.
            timeout: 10)
        return result.text
    }
    private struct Empty: Decodable {}
    private func request<T: Decodable>(path: String, token: String? = nil, body: [String: String]) async throws -> T {
        try await send(path: path, token: token, data: JSONEncoder().encode(body))
    }
    private func send<T: Decodable>(path: String, token: String?, data: Data, timeout: TimeInterval = 20) async throws
        -> T
    {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.projectURL.appendingPathComponent("/"))!)
        request.httpMethod = "POST"
        request.httpBody = data
        request.timeoutInterval = timeout
        request.setValue(Self.publicKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let (responseData, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure.unavailable }
        if status == 401 { throw Failure.unauthorized }
        if status == 400 { throw Failure.rejected }
        if status == 404 { throw Failure.setupRequired }
        if status == 429 { throw Failure.limitReached }
        guard (200...299).contains(status) else { throw Failure.unavailable }
        return try JSONDecoder().decode(T.self, from: responseData.isEmpty ? Data("{}".utf8) : responseData)
    }
}

/// Deletion confirmation belongs to one account, independently of transient UI messages.
public struct AccountDeletionConfirmation: Sendable {
    private var requestedAccount: UUID?
    private var confirmedAccount: UUID?
    public init() {}
    public mutating func request(for account: UUID) {
        requestedAccount = account
        confirmedAccount = nil
    }
    public mutating func signedIn(account: UUID, provider: String?) {
        confirmedAccount = provider == "apple" && requestedAccount == account ? account : nil
        requestedAccount = nil
    }
    public func isConfirmed(for account: UUID) -> Bool { confirmedAccount == account }
}
