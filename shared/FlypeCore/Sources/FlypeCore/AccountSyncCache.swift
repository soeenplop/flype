import Foundation

/// Backward-compatible account archives and a journal for interrupted account switches.
public struct AccountSyncCache: Codable {
    public struct Pending: Codable {
        public let account: String?
        public let entries: [PersonalDictionaryEntry]
        public let settings: SyncedSettings?
        public init(account: String?, entries: [PersonalDictionaryEntry], settings: SyncedSettings?) {
            self.account = account
            self.entries = entries
            self.settings = settings
        }
    }
    public var active: String?
    public var bases: [String: [PersonalDictionaryEntry]] = [:]
    public var archives: [String: [PersonalDictionaryEntry]] = [:]
    public var settingsBases: [String: SyncedSettings] = [:]
    public var settingsArchives: [String: SyncedSettings] = [:]
    public var pending: Pending?
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case active, bases, archives, settingsBases, settingsArchives, pending
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        active = try values.decodeIfPresent(String.self, forKey: .active)
        bases = try values.decodeIfPresent([String: [PersonalDictionaryEntry]].self, forKey: .bases) ?? [:]
        archives = try values.decodeIfPresent([String: [PersonalDictionaryEntry]].self, forKey: .archives) ?? [:]
        settingsBases = try values.decodeIfPresent([String: SyncedSettings].self, forKey: .settingsBases) ?? [:]
        settingsArchives = try values.decodeIfPresent([String: SyncedSettings].self, forKey: .settingsArchives) ?? [:]
        pending = try values.decodeIfPresent(Pending.self, forKey: .pending)
    }
    public mutating func stageSwitch(
        to account: String?, currentEntries: [PersonalDictionaryEntry], currentSettings: SyncedSettings,
        importGuest: Bool
    ) {
        archives[active ?? "guest"] = currentEntries
        settingsArchives[active ?? "guest"] = currentSettings
        let entries = archives[account ?? "guest"] ?? ((active == nil && importGuest) ? currentEntries : [])
        let settings = settingsArchives[account ?? "guest"] ?? (active == nil ? currentSettings : SyncedSettings())
        pending = Pending(account: account, entries: entries, settings: settings)
    }
    /// Removes everything kept for a deleted account, including conflict copies that were never shown.
    public mutating func forget(account: String) {
        bases[account] = nil
        settingsBases[account] = nil
        archives[account] = nil
        settingsArchives[account] = nil
        archives = archives.filter { !$0.key.hasPrefix("conflict-") }
        settingsArchives = settingsArchives.filter { !$0.key.hasPrefix("conflict-") }
    }
    public static var url: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Flype/Account/dictionaries.json")
    }
    public static func load(from url: URL = AccountSyncCache.url) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func save(to url: URL = AccountSyncCache.url) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        #if os(iOS)
            try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try JSONEncoder().encode(self).write(to: url, options: .atomic)
        #endif
    }
    public mutating func recoverSwitch(
        store: PersonalDictionaryStore?, defaults: UserDefaults = .standard,
        languageDefaults: UserDefaults = FlypePreferences.defaults, url: URL = AccountSyncCache.url
    ) throws {
        guard let pending else { return }
        guard let store else { throw PersonalDictionaryStore.Failure.unavailable }
        try store.replace(entries: pending.entries)
        pending.settings?.apply(defaults: defaults, languageDefaults: languageDefaults)
        active = pending.account
        self.pending = nil
        try save(to: url)
    }
}
