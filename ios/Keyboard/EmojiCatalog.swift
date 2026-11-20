import FlypeCore
import Foundation

/// The emoji pages of the native keyboard, with the recently used ones in front.
enum EmojiCatalog {
    enum Category: CaseIterable {
        case recent, smileysAndPeople, animalsAndNature, foodAndDrink, activity, travelAndPlaces, objects, symbols,
            flags

        var title: String {
            switch self {
            case .recent: L10n.text("Häufig benutzt")
            case .smileysAndPeople: L10n.text("Smileys & Personen")
            case .animalsAndNature: L10n.text("Tiere & Natur")
            case .foodAndDrink: L10n.text("Essen & Trinken")
            case .activity: L10n.text("Aktivitäten")
            case .travelAndPlaces: L10n.text("Reisen & Orte")
            case .objects: L10n.text("Objekte")
            case .symbols: L10n.text("Symbole")
            case .flags: L10n.text("Flaggen")
            }
        }

        var symbol: String {
            switch self {
            case .recent: "clock"
            case .smileysAndPeople: "face.smiling"
            case .animalsAndNature: "pawprint"
            case .foodAndDrink: "fork.knife"
            case .activity: "basketball"
            case .travelAndPlaces: "car"
            case .objects: "lightbulb"
            case .symbols: "music.note"
            case .flags: "flag"
            }
        }
    }

    struct Page {
        let category: Category
        let emoji: [String]
    }

    private static let recentKey = "recentEmoji"
    private static let recentLimit = 30

    /// Every page with content, so the recent page only appears once something has been sent.
    static func pages(defaults: UserDefaults = .standard) -> [Page] {
        let recent = Page(category: .recent, emoji: recentEmoji(defaults: defaults))
        return ([recent] + fixedPages).filter { !$0.emoji.isEmpty }
    }

    static func remember(_ emoji: String, defaults: UserDefaults = .standard) {
        var recent = recentEmoji(defaults: defaults)
        recent.removeAll { $0 == emoji }
        recent.insert(emoji, at: 0)
        defaults.set(Array(recent.prefix(recentLimit)), forKey: recentKey)
    }

    static func recentEmoji(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: recentKey) ?? []
    }

    private static let fixedPages: [Page] = Category.allCases.filter { $0 != .recent }.map { category in
        Page(category: category, emoji: category.allEmoji.filter(isDrawable).map(String.init))
    }

    private static func isDrawable(_ emoji: Character) -> Bool {
        if #available(iOS 26.4, *) { return true }
        return !Category.newerEmoji.contains(emoji)
    }
}
