import XCTest

@testable import FlypeCore

final class DictionarySyncTests: XCTestCase {
    func testForgettingAnAccountKeepsGuestDataAndOtherAccounts() {
        var cache = AccountSyncCache()
        let entry = PersonalDictionaryEntry(spelling: "Flype")
        cache.bases = ["a": [entry], "b": [entry]]
        cache.archives = ["a": [entry], "b": [entry], "guest": [entry], "conflict-local-1": [entry]]
        cache.settingsBases = ["a": SyncedSettings()]
        cache.settingsArchives = [
            "a": SyncedSettings(), "guest": SyncedSettings(), "conflict-remote-1": SyncedSettings(),
        ]
        cache.forget(account: "a")
        XCTAssertEqual(Set(cache.bases.keys), ["b"])
        XCTAssertEqual(Set(cache.archives.keys), ["b", "guest"])
        XCTAssertTrue(cache.settingsBases.isEmpty)
        XCTAssertEqual(Set(cache.settingsArchives.keys), ["guest"])
    }
    func testOfflineAdditionAndRemoteEditAreMerged() throws {
        let a = PersonalDictionaryEntry(spelling: "Flype")
        var changed = a
        changed.enabled = false
        let b = PersonalDictionaryEntry(spelling: "Parakeet")
        let result = try DictionaryMerge.merge(base: [a], local: [a, b], remote: [changed])
        XCTAssertEqual(Set(result.map(\.spelling)), ["Flype", "Parakeet"])
        XCTAssertEqual(result.first { $0.id == a.id }, changed)
    }
    func testDeletionIsNotResurrected() throws {
        let a = PersonalDictionaryEntry(spelling: "Flype")
        XCTAssertTrue(try DictionaryMerge.merge(base: [a], local: [], remote: [a]).isEmpty)
    }
    func testConcurrentChangeAndDeleteRequireDecision() {
        let a = PersonalDictionaryEntry(spelling: "Flype")
        var changed = a
        changed.spelling = "Flype Pro"
        XCTAssertThrowsError(try DictionaryMerge.merge(base: [a], local: [], remote: [changed]))
    }
    func testDistinctIndependentAdditionsWithSameSpellingCollapse() throws {
        let a = PersonalDictionaryEntry(spelling: "Flype")
        let b = PersonalDictionaryEntry(spelling: "Flype")
        XCTAssertEqual(try DictionaryMerge.merge(base: [], local: [a], remote: [b]).count, 1)
    }
    func testAliasedCollisionIsPreservedAsConflict() {
        let a = PersonalDictionaryEntry(spelling: "Flype", aliases: ["Fleib"])
        let b = PersonalDictionaryEntry(spelling: "Fleib")
        XCTAssertThrowsError(try DictionaryMerge.merge(base: [], local: [a], remote: [b]))
    }
    func testFirstRemotePullCanReplaceEmptyStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalDictionaryStore(directory: directory)
        let empty = try store.snapshot()
        XCTAssertEqual(empty.revision, try store.snapshot().revision)
        try store.replace(entries: [.init(spelling: "Flype")], expectedRevision: empty.revision)
        XCTAssertEqual(try store.snapshot().entries.first?.spelling, "Flype")
    }
    func testTokenResponseDecodingAndExpiry() throws {
        let data = Data(
            #"{"access_token":"test-only-access","refresh_token":"test-only-refresh","expires_in":3600,"user":{"id":"00000000-0000-0000-0000-000000000001","email":"test@example.invalid"}}"#
                .utf8)
        var session = try JSONDecoder().decode(CloudSession.self, from: data)
        XCTAssertEqual(session.accessToken, "test-only-access")
        XCTAssertTrue(session.needsRefresh)
        session.savedAt = Date()
        XCTAssertFalse(session.needsRefresh)
        session.savedAt = Date().addingTimeInterval(-3601)
        XCTAssertTrue(session.needsRefresh)
        XCTAssertEqual(
            try JSONDecoder().decode(CloudSession.self, from: JSONEncoder().encode(session)).refreshToken,
            "test-only-refresh")
    }
    func testAtomicReplacementRejectsStaleRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalDictionaryStore(directory: directory)
        try store.upsert(.init(spelling: "Flype"))
        let old = try store.snapshot()
        try store.upsert(.init(spelling: "Anna"))
        XCTAssertThrowsError(try store.replace(entries: [], expectedRevision: old.revision))
        XCTAssertEqual(try store.snapshot().entries.count, 2)
    }
    func testReplacementValidatesAllEntriesBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersonalDictionaryStore(directory: directory)
        try store.upsert(.init(spelling: "Flype"))
        XCTAssertThrowsError(try store.replace(entries: [.init(spelling: "X"), .init(spelling: "x")]))
        XCTAssertEqual(try store.snapshot().entries.first?.spelling, "Flype")
    }
    func testOAuthUsesPKCEAndOnlyExpectedCallback() throws {
        let url = SupabaseAPI().authorizationURL(
            provider: "google", callback: "flype://auth/callback", challenge: "test-challenge")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "leystmzdybimmbaruywp.supabase.co")
        XCTAssertTrue(parts.queryItems!.contains(.init(name: "code_challenge_method", value: "s256")))
        XCTAssertFalse(url.absoluteString.contains("secret"))
    }
}
