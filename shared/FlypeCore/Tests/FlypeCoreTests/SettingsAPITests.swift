import Foundation
import XCTest

@testable import FlypeCore

private final class SyncProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == SupabaseAPI.projectURL.host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: code, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class SettingsAPITests: XCTestCase, @unchecked Sendable {
    private func api() -> SupabaseAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SyncProtocol.self]
        return SupabaseAPI(session: URLSession(configuration: config))
    }
    override func tearDown() {
        SyncProtocol.handler = nil
        super.tearDown()
    }
    func testFirstSettingsReadUsesAuthenticatedRPCAndDecodesMissingRemoteSnapshot() async throws {
        SyncProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/flype_read_settings")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            return (200, Data(#"{"revision":0,"settings":null}"#.utf8))
        }
        let result = try await api().readSettings(token: "unit-test-token")
        XCTAssertEqual(result.revision, 0)
        XCTAssertNil(result.settings)
    }
    func testRevisionConflictReturnsTheActualServerSettings() async throws {
        SyncProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/flype_write_settings")
            // URLSession may expose the encoded body as a stream to a protocol implementation.
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(buffer, count: count)
                }
                body = data
            }
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
            XCTAssertEqual(json["expected_revision"] as? Int, 3)
            XCTAssertEqual((json["p_settings"] as? [String: Any])?["speechProvider"] as? String, "parakeet")
            XCTAssertEqual((json["p_settings"] as? [String: Any])?["dictationLanguage"] as? String, "en")
            return (
                200,
                Data(
                    #"{"revision":4,"applied":false,"settings":{"dictationMode":"cleaned","applyDictionary":true,"dictationLanguage":"fr","interfaceLanguage":"system"}}"#
                        .utf8)
            )
        }
        let result = try await api().writeSettings(
            token: "unit-test-token", revision: 3,
            settings: SyncedSettings(speechProvider: .parakeet, dictationLanguage: .en))
        XCTAssertEqual(result.applied, false)
        XCTAssertEqual(result.revision, 4)
        XCTAssertEqual(result.settings?.dictationLanguage, .fr)
        XCTAssertNil(result.settings?.speechProvider)
    }
    func testRejectedRefreshTokenRequiresNewSignInButServerOutageDoesNot() async {
        for (code, expectsExpiry) in [(400, true), (401, true), (500, false)] {
            SyncProtocol.handler = { _ in (code, Data("{}".utf8)) }
            do {
                _ = try await api().refresh(token: "unit-test-token")
                XCTFail("Expected a server error")
            } catch SupabaseAPI.Failure.sessionExpired {
                XCTAssertTrue(expectsExpiry, "\(code)")
            } catch {
                XCTAssertFalse(expectsExpiry, "\(code)")
            }
        }
    }
    func testAccountDeletionCallsTheAuthenticatedFunction() async throws {
        SyncProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/flype_delete_account")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        try await api().deleteAccount(token: "unit-test-token")
    }
    func testSessionKeepsTheProviderTokenAndSignInMethod() throws {
        let json =
            #"{"access_token":"a","refresh_token":"r","expires_in":3600,"provider_refresh_token":"apple","user":{"id":"00000000-0000-0000-0000-000000000001","email":null,"app_metadata":{"provider":"apple"}}}"#
        let session = try JSONDecoder().decode(CloudSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.providerRefreshToken, "apple")
        XCTAssertEqual(session.user.metadata?.provider, "apple")
        let restored = try JSONDecoder().decode(CloudSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.providerRefreshToken, "apple")
    }
    func testRejectedDataWriteIsNotReportedAsMissingSetup() async {
        SyncProtocol.handler = { _ in (400, Data("{}".utf8)) }
        do {
            _ = try await api().readSettings(token: "unit-test-token")
            XCTFail("Expected a server error")
        } catch {
            guard case SupabaseAPI.Failure.rejected = error else { return XCTFail("Wrong failure") }
        }
    }
    func testUnauthorizedAndUnconfiguredBackendsCannotLookLikeASuccessfulSync() async {
        for code in [401, 404] {
            SyncProtocol.handler = { _ in (code, Data("{}".utf8)) }
            do {
                _ = try await api().readSettings(token: "unit-test-token")
                XCTFail("Expected a server error")
            } catch {
                if code == 401 {
                    guard case SupabaseAPI.Failure.unauthorized = error else {
                        return XCTFail("Wrong authentication failure")
                    }
                } else {
                    guard case SupabaseAPI.Failure.setupRequired = error else { return XCTFail("Wrong setup failure") }
                }
            }
        }
    }
    private func appleSession(providerFields: String = #","provider_refresh_token":"apple-refresh""#) throws
        -> CloudSession
    {
        try JSONDecoder().decode(
            CloudSession.self,
            from: Data(
                (#"{"access_token":"a","refresh_token":"r","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","app_metadata":{"provider":"apple"}}"#
                    + providerFields + "}").utf8))
    }
    func testAppleRevocationFailureNeverCallsDeletion() async throws {
        for status in [400, 401, 502, 503] {
            SyncProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/functions/v1/revoke-apple-token")
                return (status, Data("{}".utf8))
            }
            do {
                try await api().deleteAccount(session: appleSession())
                XCTFail("Revocation failure must retain the account")
            } catch SupabaseAPI.Failure.appleRevocationUnavailable {} catch { XCTFail("Wrong error: \(error)") }
        }
    }
    func testAppleRevokesBeforeDeletingWithRefreshOrAccessToken() async throws {
        for fields in [#","provider_refresh_token":"apple-refresh""#, #","provider_token":"apple-access""#] {
            var paths: [String] = []
            SyncProtocol.handler = { request in
                let path = request.url!.path
                paths.append(path)
                if path.contains("revoke") {
                    var data = request.httpBody
                    if data == nil, let stream = request.httpBodyStream {
                        stream.open()
                        defer { stream.close() }
                        var bytes = Data()
                        var buffer = [UInt8](repeating: 0, count: 1024)
                        while stream.hasBytesAvailable {
                            let count = stream.read(&buffer, maxLength: buffer.count)
                            if count <= 0 { break }
                            bytes.append(buffer, count: count)
                        }
                        data = bytes
                    }
                    let body = try JSONDecoder().decode([String: String].self, from: XCTUnwrap(data))
                    XCTAssertEqual(
                        body["provider_token"],
                        fields.contains("provider_refresh_token") ? "apple-refresh" : "apple-access")
                    XCTAssertEqual(
                        body["token_type_hint"],
                        fields.contains("provider_refresh_token") ? "refresh_token" : "access_token")
                }
                return (200, Data((path.contains("revoke") ? "{}" : #"{"deleted":true}"#).utf8))
            }
            let session = try appleSession(providerFields: fields)
            XCTAssertNotNil(session.appleRevocationToken)
            let restored = try JSONDecoder().decode(CloudSession.self, from: JSONEncoder().encode(session))
            XCTAssertEqual(restored.appleRevocationToken?.value, session.appleRevocationToken?.value)
            try await api().deleteAccount(session: restored)
            XCTAssertEqual(paths, ["/functions/v1/revoke-apple-token", "/rest/v1/rpc/flype_delete_account"])
        }
    }
    func testAppleMissingCredentialCannotSilentlyDelete() async throws {
        SyncProtocol.handler = { _ in
            XCTFail("No request without an Apple credential")
            return (200, Data("{}".utf8))
        }
        do {
            try await api().deleteAccount(session: appleSession(providerFields: ""))
            XCTFail("Missing credential")
        } catch SupabaseAPI.Failure.appleRevocationUnavailable {} catch { XCTFail("Wrong error") }
    }
    func testFalseDeletionResponseIsNotSuccess() async {
        SyncProtocol.handler = { _ in (200, Data(#"{"deleted":false}"#.utf8)) }
        do {
            try await api().deleteAccount(token: "test")
            XCTFail("Not deleted")
        } catch {}
    }
    func testDeletionReauthenticationBelongsToTheRequestedAppleAccount() {
        let account = UUID()
        let other = UUID()
        var confirmation = AccountDeletionConfirmation()
        confirmation.request(for: account)
        confirmation.signedIn(account: account, provider: "apple")
        XCTAssertTrue(confirmation.isConfirmed(for: account))
        XCTAssertFalse(confirmation.isConfirmed(for: other))
        confirmation.request(for: account)
        confirmation.signedIn(account: other, provider: "apple")
        XCTAssertFalse(confirmation.isConfirmed(for: account))
        XCTAssertFalse(confirmation.isConfirmed(for: other))
        confirmation.request(for: account)
        confirmation.signedIn(account: account, provider: "google")
        XCTAssertFalse(confirmation.isConfirmed(for: account))
    }

}

extension SettingsAPITests {
    func testCloudCleanupUsesTheUserTokenAndNeverTheProviderKey() async throws {
        SyncProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/functions/v1/cloud-cleanup")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer unit-test-token")
            XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
            return (200, Data(#"{"text":"Sauberer Text."}"#.utf8))
        }
        let text = try await api().cleanDictation(token: "unit-test-token", text: "ähm Text", terms: [], language: .de)
        XCTAssertEqual(text, "Sauberer Text.")
    }
    func testCloudCleanupReportsLimitsAndExpiredSessions() async throws {
        for (status, expected) in [(429, SupabaseAPI.Failure.limitReached), (401, .unauthorized), (503, .unavailable)] {
            SyncProtocol.handler = { _ in (status, Data()) }
            do {
                _ = try await api().cleanDictation(token: "unit-test-token", text: "Text", terms: [], language: .de)
                XCTFail("Status \(status) must fail")
            } catch let failure as SupabaseAPI.Failure {
                XCTAssertEqual(failure, expected)
            }
        }
    }
    func testCloudCleanupIsOffUntilSomeoneOptsIn() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "flype.tests.cloud-cleanup"))
        defaults.removePersistentDomain(forName: "flype.tests.cloud-cleanup")
        XCTAssertFalse(CloudCleanup.isEnabled(defaults: defaults))
        defaults.set(true, forKey: CloudCleanup.consentKey)
        XCTAssertTrue(CloudCleanup.isEnabled(defaults: defaults))
    }
}
