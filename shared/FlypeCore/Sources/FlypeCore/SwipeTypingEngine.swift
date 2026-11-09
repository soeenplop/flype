import CoreGraphics
import Foundation

/// Loads word lists and decodes swipes away from the thread that delivers touches.
public actor SwipeTypingEngine {
    private let locate: @Sendable (FlypeLanguage) -> URL?
    private let dictionary: @Sendable () -> PersonalDictionaryStore?
    private let learning: @Sendable () -> WordLearningStore?
    private var loaded: (language: FlypeLanguage, list: CombinedWordList)?

    public init(
        locate: @escaping @Sendable (FlypeLanguage) -> URL?,
        dictionary: @escaping @Sendable () -> PersonalDictionaryStore? = { try? .shared() },
        learning: @escaping @Sendable () -> WordLearningStore? = { try? .shared() }
    ) {
        self.locate = locate
        self.dictionary = dictionary
        self.learning = learning
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

    /// Counts a corrected word, and adds it to the personal dictionary once it was corrected the same way twice.
    /// A word the list can already produce was not missing, and a replacement that does not fit the path is a change
    /// of mind, not a correction. Returns whether the word was added.
    @discardableResult
    public func learn(_ correction: SwipeCorrection) -> Bool {
        guard let word = correction.learnableWord, isUnknown(word, language: correction.language) else { return false }
        if !correction.extendsSwipedWord,
            !SwipeDecoder.fits(word, path: correction.path, layout: correction.layout)
        {
            return false
        }
        return count(word, as: .correction)
    }

    /// Counts a word typed letter by letter, and adds it once it was typed three times. Returns whether it was added.
    @discardableResult
    public func noteTyped(_ text: String, language: FlypeLanguage, startsSentence: Bool) -> Bool {
        guard let word = WordLearning.learnable(text, startsSentence: startsSentence),
            isUnknown(word, language: language)
        else { return false }
        return count(word, as: .typing)
    }

    private func isUnknown(_ word: String, language: FlypeLanguage) -> Bool {
        guard prepare(language), let list = loaded?.list, !list.contains(word),
            let entries = try? dictionary()?.snapshot().entries
        else { return false }
        let key = word.lowercased()
        return !entries.contains { ([$0.spelling] + $0.aliases).contains { $0.lowercased() == key } }
    }

    private func count(_ word: String, as source: WordLearningStore.Source) -> Bool {
        guard let learning = learning(), let store = dictionary(),
            let counts = try? learning.record(word, as: source)
        else { return false }
        let entry: PersonalDictionaryEntry
        switch source {
        case .correction:
            guard counts.corrections >= WordLearning.correctionsNeeded else { return false }
            entry = PersonalDictionaryEntry(spelling: word, learnedFromCorrection: true)
        case .typing:
            guard counts.typings >= WordLearning.typingsNeeded else { return false }
            entry = PersonalDictionaryEntry(spelling: word, learnedFromTyping: true)
        }
        do {
            try store.upsert(entry)
            try? learning.remove(word)
            return true
        } catch {
            // The dictionary is full. The count stays, so a later attempt can still succeed.
            return false
        }
    }

    private func personalWords() -> [String] {
        guard let entries = try? dictionary()?.snapshot().entries else { return [] }
        return entries.filter { $0.enabled && $0.useForTyping && !$0.spelling.contains(where: \.isWhitespace) }
            .map(\.spelling)
    }
}
