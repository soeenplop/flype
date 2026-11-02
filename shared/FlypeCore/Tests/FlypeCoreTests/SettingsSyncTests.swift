import Foundation
import XCTest

@testable import FlypeCore

final class ParakeetDefaultTests: XCTestCase {
    func testExistingInstallationsAdoptParakeetOnceAndKeepLaterChoices() {
        let name = "ParakeetDefaultTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("apple", forKey: "speechProvider")
        SpeechProvider.adoptParakeetDefault(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "speechProvider"), "parakeet")
        defaults.set("apple", forKey: "speechProvider")
        SpeechProvider.adoptParakeetDefault(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "speechProvider"), "apple")
    }
    func testParakeetIsTheDefaultForNewInstallationsAndSettings() {
        let name = "ParakeetDefaultTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(DictationOptions.current(defaults: defaults).provider, .parakeet)
        XCTAssertEqual(SyncedSettings.current(defaults: defaults, languageDefaults: defaults).speechProvider, .parakeet)
        XCTAssertEqual(SyncedSettings().speechProvider, .parakeet)
    }
}

final class SettingsSyncTests: XCTestCase {
    func testPortablePreferencesUseTheRightStoresAndIncludeModelChoice() throws {
        let appName = "FlypeTest-" + UUID().uuidString
        let groupName = "FlypeTest-" + UUID().uuidString
        let app = try XCTUnwrap(UserDefaults(suiteName: appName))
        let group = try XCTUnwrap(UserDefaults(suiteName: groupName))
        defer {
            app.removePersistentDomain(forName: appName)
            group.removePersistentDomain(forName: groupName)
        }
        app.set("apple", forKey: "speechProvider")
        app.set(false, forKey: "modelInstalled")
        app.set(true, forKey: "cleanedDefaultAdopted")
        let expected = SyncedSettings(
            speechProvider: .parakeet, dictationMode: .verbatim, dictationLanguage: .fr,
            interfaceLanguage: .it)
        expected.apply(defaults: app, languageDefaults: group)
        XCTAssertEqual(SyncedSettings.current(defaults: app, languageDefaults: group), expected)
        XCTAssertEqual(app.string(forKey: "speechProvider"), "parakeet")
        XCTAssertTrue(app.bool(forKey: "cleanedDefaultAdopted"))
        XCTAssertFalse(app.bool(forKey: "modelInstalled"))
        XCTAssertNil(group.string(forKey: "speechProvider"))
        XCTAssertNil(app.string(forKey: "dictationLanguage"))
        XCTAssertNil(group.string(forKey: "dictationMode"))
    }
    func testWireFormatContainsOnlyTheFiveApprovedPreferences() throws {
        let data = try JSONEncoder().encode(SyncedSettings())
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(values.keys),
            ["speechProvider", "dictationMode", "applyDictionary", "dictationLanguage", "interfaceLanguage"])
        for invalid in [
            "{\"dictationMode\":\"invalid\",\"applyDictionary\":true,\"dictationLanguage\":\"de\",\"interfaceLanguage\":\"system\"}",
            "{\"dictationMode\":\"cleaned\",\"applyDictionary\":true,\"dictationLanguage\":\"xx\",\"interfaceLanguage\":\"system\"}",
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(SyncedSettings.self, from: Data(invalid.utf8)))
        }
    }
    func testDictationKeyReachesOtherDevicesAndKeepsTheirLocalChoice() throws {
        let unset = SyncedSettings()
        let first = SyncedSettings(dictationKey: DictationKey(keyCode: 61))
        let second = SyncedSettings(dictationKey: DictationKey(keyCode: 96))
        XCTAssertEqual(try SettingsMerge.merge(base: nil, local: unset, remote: first).dictationKey, first.dictationKey)
        XCTAssertEqual(try SettingsMerge.merge(base: nil, local: first, remote: unset).dictationKey, first.dictationKey)
        XCTAssertEqual(
            try SettingsMerge.merge(base: unset, local: unset, remote: first).dictationKey, first.dictationKey)
        XCTAssertEqual(
            try SettingsMerge.merge(base: unset, local: first, remote: unset).dictationKey, first.dictationKey)
        XCTAssertEqual(
            try SettingsMerge.merge(base: first, local: first, remote: second).dictationKey, second.dictationKey)
        XCTAssertThrowsError(try SettingsMerge.merge(base: unset, local: first, remote: second))
    }
    func testDictationKeyIsStoredAndDefaultsToRightCommand() throws {
        let name = "flype-dictation-key-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(DictationKey.current(defaults: defaults), .rightCommand)
        XCTAssertNil(SyncedSettings.current(defaults: defaults, languageDefaults: defaults).dictationKey)
        let key = DictationKey(keyCode: 96)
        SyncedSettings(dictationKey: key).apply(defaults: defaults, languageDefaults: defaults)
        XCTAssertEqual(DictationKey.current(defaults: defaults), key)
        XCTAssertEqual(SyncedSettings.current(defaults: defaults, languageDefaults: defaults).dictationKey, key)
    }
    func testDictationKeyTravelsAsItsKeyCodeAndRejectsReservedKeys() throws {
        let data = try JSONEncoder().encode(SyncedSettings(dictationKey: DictationKey(keyCode: 96)))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(values["dictationKey"] as? Int, 96)
        XCTAssertNil(DictationKey(keyCode: 53))
        XCTAssertNil(DictationKey(keyCode: 57))
        XCTAssertNil(DictationKey(keyCode: 256))
        XCTAssertNil(DictationKey(keyCode: -1))
        XCTAssertThrowsError(try JSONDecoder().decode(DictationKey.self, from: Data("57".utf8)))
    }
    func testDictationKeyKnowsWhetherItStopsTyping() throws {
        XCTAssertTrue(DictationKey.rightCommand.isModifier)
        XCTAssertFalse(DictationKey.rightCommand.typesText)
        let function = try XCTUnwrap(DictationKey(keyCode: 96))
        XCTAssertFalse(function.isModifier)
        XCTAssertFalse(function.typesText)
        XCTAssertTrue(try XCTUnwrap(DictationKey(keyCode: 40)).typesText)
    }
    func testLegacySnapshotDoesNotResetTheLocalModelOnFirstSyncOrApply() throws {
        let legacy = try JSONDecoder().decode(
            SyncedSettings.self,
            from: Data(
                #"{"dictationMode":"cleaned","applyDictionary":true,"dictationLanguage":"de","interfaceLanguage":"system"}"#
                    .utf8))
        XCTAssertNil(legacy.speechProvider)
        let local = SyncedSettings(speechProvider: .parakeet)
        XCTAssertEqual(try SettingsMerge.merge(base: nil, local: local, remote: legacy).speechProvider, .parakeet)
        XCTAssertEqual(try SettingsMerge.merge(base: legacy, local: local, remote: legacy).speechProvider, .parakeet)
        let name = "FlypeTest-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("parakeet", forKey: "speechProvider")
        legacy.apply(defaults: defaults, languageDefaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "speechProvider"), "parakeet")
    }
    func testModelChoiceMergesWithLanguageEditsAndPreservesAnInFlightModelChange() throws {
        let base = SyncedSettings()
        var local = base
        local.dictationLanguage = .fr
        var remote = base
        remote.speechProvider = .parakeet
        let merged = try SettingsMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.speechProvider, .parakeet)
        XCTAssertEqual(merged.dictationLanguage, .fr)
        XCTAssertEqual(try SettingsMerge.merge(base: base, local: remote, remote: local), merged)
        XCTAssertEqual(try SettingsMerge.merge(base: nil, local: base, remote: remote).speechProvider, .parakeet)
    }
    func testUnknownModelChoiceIsRejected() throws {
        let data = try JSONEncoder().encode(SyncedSettings())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["speechProvider"] = "unsupported"
        XCTAssertThrowsError(
            try JSONDecoder().decode(SyncedSettings.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testOfflineEditsToDifferentPreferencesAreCombined() throws {
        let base = SyncedSettings()
        var local = base
        local.dictationMode = .verbatim
        var remote = base
        remote.dictationLanguage = .fr
        remote.interfaceLanguage = .es
        let merged = try SettingsMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(merged.dictationMode, .verbatim)
        XCTAssertEqual(merged.dictationLanguage, .fr)
        XCTAssertEqual(merged.interfaceLanguage, .es)
    }
    func testConflictingLanguageChangesPreserveBothInputs() {
        let base = SyncedSettings()
        var local = base
        local.dictationLanguage = .en
        var remote = base
        remote.dictationLanguage = .fr
        XCTAssertThrowsError(try SettingsMerge.merge(base: base, local: local, remote: remote)) { error in
            XCTAssertEqual((error as? SettingsMerge.Conflict)?.fields, ["dictationLanguage"])
        }
        XCTAssertEqual(local.dictationLanguage, .en)
        XCTAssertEqual(remote.dictationLanguage, .fr)
    }
    func testIdenticalChangesDoNotConflictAndFirstPullUsesAccountSettings() throws {
        let base = SyncedSettings()
        let remote = SyncedSettings(dictationLanguage: .nl)
        XCTAssertEqual(try SettingsMerge.merge(base: base, local: remote, remote: remote), remote)
        XCTAssertEqual(try SettingsMerge.merge(base: nil, local: base, remote: remote), remote)
        XCTAssertEqual(try SettingsMerge.merge(base: nil, local: remote, remote: nil), remote)
    }
    func testAnOldDisabledDictionaryChoiceIsReplacedWithoutAConflict() throws {
        let disabled = try JSONDecoder().decode(
            SyncedSettings.self,
            from: Data(
                #"{"dictationMode":"cleaned","applyDictionary":false,"dictationLanguage":"de","interfaceLanguage":"system"}"#
                    .utf8))
        XCTAssertFalse(disabled.applyDictionary)
        let local = SyncedSettings()
        XCTAssertTrue(try SettingsMerge.merge(base: nil, local: local, remote: disabled).applyDictionary)
        XCTAssertTrue(try SettingsMerge.merge(base: disabled, local: local, remote: disabled).applyDictionary)
    }
    func testRebasePreservesAnEditMadeWhileTheServerRequestWasRunning() throws {
        let sent = SyncedSettings()
        var newest = sent
        newest.dictationMode = .verbatim
        var accepted = sent
        accepted.interfaceLanguage = .en
        let result = try SettingsMerge.merge(base: sent, local: newest, remote: accepted)
        XCTAssertEqual(result.dictationMode, .verbatim)
        XCTAssertEqual(result.interfaceLanguage, .en)
    }
    func testRebaseCannotOverwriteANewerConflictingPreference() {
        let sent = SyncedSettings()
        var newest = sent
        newest.interfaceLanguage = .fr
        var accepted = sent
        accepted.interfaceLanguage = .en
        XCTAssertThrowsError(try SettingsMerge.merge(base: sent, local: newest, remote: accepted))
    }
    func testLegacyAccountCacheDecodesWithoutSettingsAndRetainsItsJournal() throws {
        let cache = try JSONDecoder().decode(
            AccountSyncCache.self,
            from: Data(
                #"{"active":"account-a","bases":{},"archives":{},"pending":{"account":"account-b","entries":[]}}"#.utf8)
        )
        XCTAssertEqual(cache.active, "account-a")
        XCTAssertEqual(cache.pending?.account, "account-b")
        XCTAssertNil(cache.pending?.settings)
        XCTAssertTrue(cache.settingsBases.isEmpty)
    }
    func testAccountSwitchDoesNotLeakAnotherAccountsWordsOrPreferences() throws {
        var cache = AccountSyncCache()
        cache.active = "account-a"
        let a = [PersonalDictionaryEntry(spelling: "Only A")]
        let settings = SyncedSettings(dictationLanguage: .fr)
        cache.stageSwitch(to: "account-b", currentEntries: a, currentSettings: settings, importGuest: true)
        XCTAssertEqual(cache.archives["account-a"], a)
        XCTAssertEqual(cache.settingsArchives["account-a"], settings)
        XCTAssertEqual(cache.pending?.entries, [])
        XCTAssertEqual(cache.pending?.settings, SyncedSettings())
        cache.active = "account-b"
        cache.stageSwitch(to: "account-a", currentEntries: [], currentSettings: SyncedSettings(), importGuest: false)
        XCTAssertEqual(cache.pending?.entries, a)
        XCTAssertEqual(cache.pending?.settings, settings)
    }
    func testGuestImportAndGuestRestorationAreSeparateFromTheAccount() {
        var cache = AccountSyncCache()
        let guest = [PersonalDictionaryEntry(spelling: "Guest word")]
        let guestSettings = SyncedSettings(dictationLanguage: .es)
        cache.stageSwitch(to: "account-a", currentEntries: guest, currentSettings: guestSettings, importGuest: false)
        XCTAssertEqual(cache.pending?.entries, [])
        XCTAssertEqual(cache.pending?.settings, guestSettings)
        cache.active = "account-a"
        cache.stageSwitch(to: nil, currentEntries: [], currentSettings: SyncedSettings(), importGuest: false)
        XCTAssertEqual(cache.pending?.entries, guest)
        XCTAssertEqual(cache.pending?.settings, guestSettings)
    }
    func testInterruptedSwitchRecoversWordsAndSettingsTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "FlypeTest-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = PersonalDictionaryStore(directory: directory.appendingPathComponent("words"))
        let url = directory.appendingPathComponent("cache.json")
        var cache = AccountSyncCache()
        let words = [PersonalDictionaryEntry(spelling: "Recovered")]
        let settings = SyncedSettings(dictationLanguage: .it)
        cache.pending = .init(account: "account-b", entries: words, settings: settings)
        try cache.save(to: url)
        cache = try AccountSyncCache.load(from: url)
        try cache.recoverSwitch(store: store, defaults: defaults, languageDefaults: defaults, url: url)
        XCTAssertEqual(try store.snapshot().entries, words)
        XCTAssertEqual(SyncedSettings.current(defaults: defaults, languageDefaults: defaults), settings)
        XCTAssertEqual(cache.active, "account-b")
        XCTAssertNil(try AccountSyncCache.load(from: url).pending)
        try cache.recoverSwitch(store: store, defaults: defaults, languageDefaults: defaults, url: url)
        XCTAssertEqual(try store.snapshot().entries, words)
    }
}
