import Foundation

/// Only portable preferences belong to the account. Model downloads, permissions and setup stay local.
public struct SyncedSettings: Codable, Equatable, Sendable {
    public enum InterfaceLanguage: String, Codable, Sendable {
        case system, de, en, fr, it, es, nl
    }
    /// Missing in legacy snapshots; an absent choice must never reset an existing device preference.
    public var speechProvider: SpeechProvider?
    public var dictationMode: DictationMode
    /// No longer a choice, because personal words only apply once someone adds them. The server still
    /// requires this field, and older clients read it.
    public var applyDictionary = true
    public var dictationLanguage: FlypeLanguage
    public var interfaceLanguage: InterfaceLanguage
    /// Only chosen on the Mac. Other devices pass it on, and absent means nobody has changed it.
    public var dictationKey: DictationKey?
    public init(
        speechProvider: SpeechProvider? = .parakeet, dictationMode: DictationMode = .cleaned,
        dictationLanguage: FlypeLanguage = .de, interfaceLanguage: InterfaceLanguage = .system,
        dictationKey: DictationKey? = nil
    ) {
        self.speechProvider = speechProvider
        self.dictationMode = dictationMode
        self.dictationLanguage = dictationLanguage
        self.interfaceLanguage = interfaceLanguage
        self.dictationKey = dictationKey
    }
    public static func current(
        defaults: UserDefaults = .standard, languageDefaults: UserDefaults = FlypePreferences.defaults
    ) -> Self {
        Self(
            speechProvider: SpeechProvider(rawValue: defaults.string(forKey: "speechProvider") ?? "parakeet")
                ?? .parakeet,
            dictationMode: DictationMode(rawValue: defaults.string(forKey: "dictationMode") ?? "cleaned") ?? .cleaned,
            dictationLanguage: FlypeLanguage.recognition(defaults: languageDefaults),
            interfaceLanguage: InterfaceLanguage(
                rawValue: languageDefaults.string(forKey: "interfaceLanguage") ?? "system") ?? .system,
            dictationKey: DictationKey.stored(in: defaults))
    }
    public func apply(defaults: UserDefaults = .standard, languageDefaults: UserDefaults = FlypePreferences.defaults) {
        if let speechProvider, defaults.string(forKey: "speechProvider") != speechProvider.rawValue {
            defaults.set(speechProvider.rawValue, forKey: "speechProvider")
        }
        if defaults.string(forKey: "dictationMode") != dictationMode.rawValue {
            defaults.set(dictationMode.rawValue, forKey: "dictationMode")
        }
        if let dictationKey, DictationKey.stored(in: defaults) != dictationKey {
            defaults.set(Int(dictationKey.keyCode), forKey: "dictationKey")
        }
        if languageDefaults.string(forKey: "dictationLanguage") != dictationLanguage.rawValue {
            languageDefaults.set(dictationLanguage.rawValue, forKey: "dictationLanguage")
        }
        if languageDefaults.string(forKey: "interfaceLanguage") != interfaceLanguage.rawValue {
            languageDefaults.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
        }
    }
}

public struct CloudSettings: Codable, Sendable {
    public let revision: Int
    public let settings: SyncedSettings?
    public let applied: Bool?
}

/// Merge each preference independently; genuinely conflicting changes require a user choice.
public enum SettingsMerge {
    public struct Conflict: Error, Equatable {
        public let fields: [String]
        public init(fields: [String]) { self.fields = fields }
    }
    public static func merge(base: SyncedSettings?, local: SyncedSettings, remote: SyncedSettings?) throws
        -> SyncedSettings
    {
        guard let remote else { return local }
        // On a device's first account sync, existing account preferences take precedence.
        guard let base else {
            var result = remote
            result.applyDictionary = true
            if result.speechProvider == nil { result.speechProvider = local.speechProvider }
            if result.dictationKey == nil { result.dictationKey = local.dictationKey }
            return result
        }
        var result = local
        var conflicts: [String] = []
        func mergeField<T: Equatable>(_ key: WritableKeyPath<SyncedSettings, T>, _ name: String) {
            if local[keyPath: key] == base[keyPath: key] {
                result[keyPath: key] = remote[keyPath: key]
            } else if remote[keyPath: key] != base[keyPath: key], local[keyPath: key] != remote[keyPath: key] {
                conflicts.append(name)
            }
        }
        if remote.speechProvider != nil {
            if base.speechProvider == nil {
                result.speechProvider = remote.speechProvider
            } else {
                mergeField(\.speechProvider, "speechProvider")
            }
        }
        if remote.dictationKey != nil {
            if base.dictationKey == nil, local.dictationKey == nil {
                result.dictationKey = remote.dictationKey
            } else {
                mergeField(\.dictationKey, "dictationKey")
            }
        }
        mergeField(\.dictationMode, "dictationMode")
        mergeField(\.dictationLanguage, "dictationLanguage")
        mergeField(\.interfaceLanguage, "interfaceLanguage")
        guard conflicts.isEmpty else { throw Conflict(fields: conflicts) }
        return result
    }
}
