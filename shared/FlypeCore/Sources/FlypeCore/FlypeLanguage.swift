import Foundation

public enum FlypePreferences {
    public static var defaults: UserDefaults {
        #if os(iOS)
            return UserDefaults(suiteName: ResultStore.appGroup) ?? .standard
        #else
            return .standard
        #endif
    }
}

public enum FlypeLanguage: String, Codable, CaseIterable, Sendable {
    case de, en, fr, it, es, nl

    public var name: String {
        switch self {
        case .de: "Deutsch"
        case .en: "English"
        case .fr: "Français"
        case .it: "Italiano"
        case .es: "Español"
        case .nl: "Nederlands"
        }
    }
    public var localeIdentifier: String {
        switch self {
        case .de: "de-DE"
        case .en: "en-US"
        case .fr: "fr-FR"
        case .it: "it-IT"
        case .es: "es-ES"
        case .nl: "nl-NL"
        }
    }
    public var spellingIdentifier: String { localeIdentifier.replacingOccurrences(of: "-", with: "_") }
    public var keyboardRows: [String] {
        switch self {
        case .de: ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"]
        case .fr: ["azertyuiop", "qsdfghjklm", "wxcvbn"]
        case .es: ["qwertyuiop", "asdfghjklñ", "zxcvbnm"]
        case .en, .it, .nl: ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        }
    }
    public var startingWords: [String] {
        switch self {
        case .de: ["Ich", "Das", "Wir"]
        case .en: ["I", "The", "We"]
        case .fr: ["Je", "Le", "Nous"]
        case .it: ["Io", "Il", "Noi"]
        case .es: ["Yo", "El", "Nosotros"]
        case .nl: ["Ik", "De", "Wij"]
        }
    }
    public var connectingWords: [String] {
        switch self {
        case .de: ["und", "die", "ich"]
        case .en: ["and", "the", "I"]
        case .fr: ["et", "le", "je"]
        case .it: ["e", "il", "io"]
        case .es: ["y", "el", "yo"]
        case .nl: ["en", "de", "ik"]
        }
    }
    public static func recognition(defaults: UserDefaults = FlypePreferences.defaults) -> Self {
        Self(rawValue: defaults.string(forKey: "dictationLanguage") ?? "de") ?? .de
    }
    public static func interface(
        defaults: UserDefaults = FlypePreferences.defaults, preferred: [String] = Locale.preferredLanguages
    ) -> Self {
        let choice = defaults.string(forKey: "interfaceLanguage") ?? "system"
        if let value = Self(rawValue: choice) { return value }
        for language in preferred {
            if let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first,
                let value = Self(rawValue: String(code))
            {
                return value
            }
        }
        return .en
    }
}
