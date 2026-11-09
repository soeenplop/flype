import CoreGraphics
import Foundation

/// Loads word lists and decodes swipes away from the thread that delivers touches.
public actor SwipeTypingEngine {
    private let locate: @Sendable (FlypeLanguage) -> URL?
    private let dictionary: @Sendable () -> PersonalDictionaryStore?
    private var loaded: (language: FlypeLanguage, list: CombinedWordList)?

    public init(
        locate: @escaping @Sendable (FlypeLanguage) -> URL?,
        dictionary: @escaping @Sendable () -> PersonalDictionaryStore? = { try? .shared() }
    ) {
        self.locate = locate
        self.dictionary = dictionary
    }

    /// Maps the file instead of reading it, so only the part in use takes up memory. Safe to call repeatedly.
    @discardableResult
    public func prepare(_ language: FlypeLanguage) -> Bool {
        if loaded?.language == language { return true }
        loaded = nil
        guard let url = locate(language), let data = try? Data(contentsOf: url, options: .alwaysMapped) else {
            return false
        }
        loaded = (language, CombinedWordList(data: data))
        return true
    }

    public func candidates(
        path: [CGPoint], layout: SwipeKeyLayout, language: FlypeLanguage,
        previousWord: String?, casing: SwipeCasing, usePersonalWords: Bool, limit: Int = 3
    ) -> [String] {
        guard prepare(language), let list = loaded?.list else { return [] }
        return SwipeDecoder.candidates(
            path: path, layout: layout, list: list, personalWords: usePersonalWords ? personalWords() : [],
            previousWord: previousWord, casing: casing, limit: limit)
    }

    /// Adds a corrected word to the personal dictionary, marked as learned. Returns whether it did.
    /// A word the list can already produce was not missing, and a replacement that does not fit the path is a change
    /// of mind, not a correction.
    @discardableResult
    public func learn(_ correction: SwipeCorrection) -> Bool {
        guard let word = correction.learnableWord, prepare(correction.language), let list = loaded?.list,
            !list.contains(word), let store = dictionary()
        else { return false }
        if !correction.extendsSwipedWord,
            !SwipeDecoder.fits(word, path: correction.path, layout: correction.layout)
        {
            return false
        }
        do {
            try store.upsert(PersonalDictionaryEntry(spelling: word, learnedFromCorrection: true))
            return true
        } catch {
            // Already in the dictionary, or the dictionary is full.
            return false
        }
    }

    private func personalWords() -> [String] {
        guard let entries = try? dictionary()?.snapshot().entries else { return [] }
        return entries.filter { $0.enabled && $0.useForTyping && !$0.spelling.contains(where: \.isWhitespace) }
            .map(\.spelling)
    }
}
