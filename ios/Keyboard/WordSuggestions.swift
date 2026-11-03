import FlypeCore
import UIKit

/// UIKit's synchronous spelling API is main-actor isolated; other work belongs to the worker.
@MainActor
final class WordSuggestions {
    private let checker = UITextChecker()
    private let worker = WordSuggestionWorker()
    private var dictionaryEnabled = false
    private struct CacheKey: Hashable {
        let prefix: String
        let word: String
        let language: String
    }
    private var cache: [CacheKey: [String]] = [:]

    func setPersonalDictionaryEnabled(_ enabled: Bool) { dictionaryEnabled = enabled }
    var selectedLanguage = FlypeLanguage.de
    private var language: String? {
        UITextChecker.availableLanguages.first(where: { $0 == selectedLanguage.spellingIdentifier })
            ?? UITextChecker.availableLanguages.first(where: { $0.hasPrefix(selectedLanguage.rawValue) })
    }

    func candidates(for context: WordSuggestionContext) async -> [String] {
        guard !Task.isCancelled else { return [] }
        let selected = selectedLanguage
        let enabled = dictionaryEnabled
        var system: [String] = []
        if !context.prefix.isEmpty, context.word.count <= 48, let language {
            let key = CacheKey(prefix: context.prefix, word: context.word, language: language)
            if let cached = cache[key] {
                system = cached
            } else {
                #if DEBUG
                    system = KeyboardTouchDiagnostics.shared.measure("spelling") {
                        systemCandidates(for: context, language: language)
                    }
                #else
                    system = systemCandidates(for: context, language: language)
                #endif
                if cache.count >= 32 { cache.removeAll(keepingCapacity: true) }
                cache[key] = system
            }
        }
        let result = await worker.candidates(
            for: context, language: selected, systemCandidates: system, dictionaryEnabled: enabled)
        guard !Task.isCancelled, selected == selectedLanguage, enabled == dictionaryEnabled else { return [] }
        return result
    }

    private func systemCandidates(for context: WordSuggestionContext, language: String) -> [String] {
        let range = NSRange(location: 0, length: (context.prefix as NSString).length)
        let completions =
            checker.completions(
                forPartialWordRange: range, in: context.prefix, language: language) ?? []
        // Guesses are only needed when a word has few completions, as with a typo.
        guard completions.count < 2 else { return completions }
        let wholeRange = NSRange(location: 0, length: (context.word as NSString).length)
        let misspelled =
            checker.rangeOfMisspelledWord(
                in: context.word, range: wholeRange, startingAt: 0, wrap: false, language: language
            ).location != NSNotFound
        let guesses =
            misspelled
            ? (checker.guesses(forWordRange: wholeRange, in: context.word, language: language) ?? []) : []
        return guesses + completions
    }
}
