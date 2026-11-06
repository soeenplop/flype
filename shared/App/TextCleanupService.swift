import FlypeCore
import Foundation

/// Cleanup runs only in the cloud, after the person chose "Bereinigt" and agreed to send the text.
actor TextCleanupService {
    func clean(
        _ text: String, dictionary: DictionarySnapshot, language: FlypeLanguage = .de, cloudToken: String,
        fieldContext: String? = nil, followingText: String? = nil
    ) async throws -> String {
        // The server rejects larger requests, so they are not sent at all. Never truncate input.
        let terms = dictionary.relevantTerms(for: text)
        let context = fieldContext.map(DictationFieldContext.tail).flatMap { $0.isEmpty ? nil : $0 }
        let following = followingText.map(DictationFieldContext.head).flatMap { $0.isEmpty ? nil : $0 }
        guard
            text.utf8.count + terms.joined(separator: ", ").utf8.count + (context?.utf8.count ?? 0)
                + (following?.utf8.count ?? 0) <= 5_000
        else {
            throw CleanupError.tooLong
        }
        let result = try await SupabaseAPI().cleanDictation(
            token: cloudToken, text: text, terms: terms, language: language, context: context,
            following: following)
        try Task.checkCancellation()
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CleanupError.empty }
        return cleaned
    }
}
enum CleanupError: LocalizedError {
    case tooLong, empty
    var errorDescription: String? {
        switch self {
        case .tooLong: "Diese Transkription ist für die Bereinigung zu lang. Der Originaltext bleibt erhalten."
        case .empty: "Die KI hat keinen Text zurückgegeben. Der Originaltext bleibt erhalten."
        }
    }
}
