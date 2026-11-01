import Foundation

public enum SpeechProvider: String, Codable, CaseIterable, Sendable {
    case apple, parakeet
    public var title: String { self == .apple ? "Apple" : "Parakeet" }

    /// Adopt the new default once on existing installations; later choices remain untouched.
    public static func adoptParakeetDefault(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "parakeetDefaultAdopted") else { return }
        defaults.set(Self.parakeet.rawValue, forKey: "speechProvider")
        defaults.set(true, forKey: "parakeetDefaultAdopted")
    }
}
/// The key held to dictate on the Mac, as its hardware key code, so any key works on any keyboard layout.
public struct DictationKey: Codable, Equatable, Sendable {
    public static let rightCommand = DictationKey(uncheckedKeyCode: 54)
    public let keyCode: UInt16
    private init(uncheckedKeyCode: UInt16) { keyCode = uncheckedKeyCode }
    /// Escape cancels choosing a key. Caps Lock toggles instead of reporting when it is released.
    public init?(keyCode: Int) {
        guard (0...255).contains(keyCode), keyCode != 53, keyCode != 57 else { return nil }
        self.keyCode = UInt16(keyCode)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let key = DictationKey(keyCode: try container.decode(Int.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported dictation key")
        }
        self = key
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Int(keyCode))
    }
    public static func stored(in defaults: UserDefaults = .standard) -> Self? {
        (defaults.object(forKey: "dictationKey") as? Int).flatMap { Self(keyCode: $0) }
    }
    public static func current(defaults: UserDefaults = .standard) -> Self { stored(in: defaults) ?? .rightCommand }
    public var isModifier: Bool { [54, 55, 56, 58, 59, 60, 61, 62, 63].contains(keyCode) }
    /// Function keys have no other job while typing; every other key stops typing while it is chosen.
    public var typesText: Bool {
        !isModifier
            && ![122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90].contains(
                keyCode)
    }
}
public enum DictationMode: String, Codable, CaseIterable, Sendable {
    case verbatim, cleaned
    public var title: String { self == .verbatim ? "Wörtlich" : "Bereinigt" }

    /// Adopt the new default once on existing installations; later choices remain untouched.
    public static func adoptCleanedDefault(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "cleanedDefaultAdopted") else { return }
        defaults.set(Self.cleaned.rawValue, forKey: "dictationMode")
        defaults.set(true, forKey: "cleanedDefaultAdopted")
    }
}
public struct DictationOptions: Sendable {
    public var provider: SpeechProvider
    public var mode: DictationMode
    public var language: FlypeLanguage
    public init(
        provider: SpeechProvider, mode: DictationMode, language: FlypeLanguage = .de
    ) {
        self.provider = provider
        self.mode = mode
        self.language = language
    }
    public static func current(
        defaults: UserDefaults = .standard, languageDefaults: UserDefaults = FlypePreferences.defaults
    ) -> DictationOptions {
        DictationOptions(
            provider: SpeechProvider(rawValue: defaults.string(forKey: "speechProvider") ?? "parakeet") ?? .parakeet,
            mode: DictationMode(rawValue: defaults.string(forKey: "dictationMode") ?? "cleaned") ?? .cleaned,
            language: FlypeLanguage.recognition(defaults: languageDefaults))
    }
}
