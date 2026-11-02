import Foundation

/// File access, dictionary matching and ranking are serialized away from UIKit's main actor.
public actor WordSuggestionWorker {
    private var personal = DictionarySnapshot()
    private var lastDictionaryCheck: TimeInterval = 0
    private var dictionaryModifiedAt: Date?
    private let storeOverride: PersonalDictionaryStore?

    public init(store: PersonalDictionaryStore? = nil) { storeOverride = store }

    private func refreshDictionary() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDictionaryCheck > 2 else { return }
        lastDictionaryCheck = now
        do {
            let store = try storeOverride ?? PersonalDictionaryStore.shared()
            let attributes = try? FileManager.default.attributesOfItem(atPath: store.fileURL.path)
            let modified = attributes?[.modificationDate] as? Date
            guard modified != dictionaryModifiedAt || dictionaryModifiedAt == nil else { return }
            personal = try store.snapshot()
            dictionaryModifiedAt = modified
        } catch {
            personal = DictionarySnapshot()
            dictionaryModifiedAt = nil
        }
    }

    public func candidates(
        for context: WordSuggestionContext, language: FlypeLanguage,
        systemCandidates: [String], dictionaryEnabled: Bool
    ) -> [String] {
        if dictionaryEnabled {
            refreshDictionary()
        } else {
            personal = DictionarySnapshot()
            dictionaryModifiedAt = nil
            lastDictionaryCheck = 0
        }
        guard !context.prefix.isEmpty else {
            guard context.suffix.isEmpty else { return [] }
            let sentenceEnded =
                context.before.trimmingCharacters(in: .whitespaces).last.map { ".!?\n".contains($0) } ?? true
            if sentenceEnded { return language.startingWords }
            return (language == .de ? Self.nextWords[context.precedingWord] : nil)
                ?? language.connectingWords
        }
        guard context.word.count <= 48 else { return [context.word] }
        var words = [context.word]
        for candidate in personal.completions(prefix: context.prefix) + systemCandidates {
            let value: String
            if personal.entries.contains(where: { $0.enabled && $0.useForTyping && $0.spelling == candidate }) {
                value = candidate
            } else if context.prefix == context.prefix.uppercased(), context.prefix.count > 1 {
                value = candidate.uppercased()
            } else if context.prefix.first?.isUppercase == true {
                value = candidate.prefix(1).uppercased() + candidate.dropFirst()
            } else {
                value = candidate
            }
            guard !value.isEmpty,
                !words.contains(where: {
                    $0.precomposedStringWithCanonicalMapping.lowercased()
                        == value.precomposedStringWithCanonicalMapping.lowercased()
                })
            else { continue }
            words.append(value)
            if words.count == 3 { break }
        }
        return words
    }
    private static let nextWords: [String: [String]] = [
        "ich": ["bin", "habe", "möchte"], "du": ["bist", "hast", "kannst"],
        "wir": ["sind", "haben", "können"], "sie": ["ist", "sind", "hat"],
        "das": ["ist", "war", "wird"], "es": ["ist", "gibt", "war"],
        "guten": ["Morgen", "Tag", "Abend"], "vielen": ["Dank", "Grüßen", "Menschen"],
        "bis": ["morgen", "später", "bald"], "bin": ["ich", "gleich", "heute"],
        "habe": ["ich", "eine", "das"], "kann": ["ich", "man", "das"],
        "ist": ["das", "ein", "eine"], "mit": ["der", "dem", "dir"],
        "für": ["dich", "die", "den"], "auf": ["die", "den", "dem"],
    ]
}
