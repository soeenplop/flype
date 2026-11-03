import FlypeCore
import Foundation
import FoundationModels

@Generable
private struct CleanedDictation {
    @Guide(
        description:
            "Nur die bereinigte Transkription in der Originalsprache, ohne Vorbemerkung, Erklärung oder Anführungszeichen."
    )
    var text: String
}
actor TextCleanupService {
    static func availabilityMessage(language: FlypeLanguage = .recognition()) -> String? {
        let model = SystemLanguageModel.default
        guard model.isAvailable else {
            return
                "Die optionale Bereinigung braucht Apple Intelligence. Wörtliche Transkription bleibt auch ohne sie möglich."
        }
        guard model.supportsLocale(Locale(identifier: language.localeIdentifier)) else {
            return L10n.text("Die Bereinigung unterstützt diese Sprache momentan nicht.")
        }
        return nil
    }

    /// With a token the text goes to the cloud, and otherwise it stays on this device.
    func clean(
        _ text: String, dictionary: DictionarySnapshot, language: FlypeLanguage = .de, cloudToken: String? = nil,
        fieldContext: String? = nil
    ) async throws -> String {
        // Bound prompt + output conservatively for the iOS 26 context window. Never truncate input.
        let terms = dictionary.relevantTerms(for: text)
        let context = fieldContext.map(DictationFieldContext.tail)
        guard text.utf8.count + terms.joined(separator: ", ").utf8.count + (context?.utf8.count ?? 0) <= 5_000 else {
            throw CleanupError.tooLong
        }
        var cloudFailure: Error?
        var cloudResult: String?
        if let cloudToken {
            do {
                cloudResult = try await SupabaseAPI().cleanDictation(
                    token: cloudToken, text: text, terms: terms, language: language, context: context)
            } catch { cloudFailure = error }
            try Task.checkCancellation()
        }
        let result: String
        if let cloudResult {
            result = cloudResult
        } else {
            // Offline, a failed server or a used-up limit all fall back to the model on this device.
            if let message = Self.availabilityMessage(language: language) {
                throw cloudFailure ?? CleanupError.unavailable(message)
            }
            result = try await generateLocally(text, terms: terms, language: language, context: context)
        }
        try Task.checkCancellation()
        let cleaned = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw CleanupError.empty }
        return cleaned
    }
    private func generateLocally(
        _ text: String, terms: [String], language: FlypeLanguage, context: String?
    ) async throws -> String {
        let instructions = CleanupPrompt.instructions(language: language)
        let session = LanguageModelSession(instructions: instructions)
        var input: [String: Any] = ["transcription": text, "preferredSpellings": terms]
        if let context { input["precedingText"] = context }
        let data = try JSONSerialization.data(withJSONObject: input)
        let response = try await session.respond(
            to: String(decoding: data, as: UTF8.self), generating: CleanedDictation.self,
            options: GenerationOptions(temperature: 0, maximumResponseTokens: 1_500))
        return response.content.text
    }
}
enum CleanupError: LocalizedError {
    case unavailable(String)
    case tooLong, empty
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .tooLong: "Diese Transkription ist für die lokale Bereinigung zu lang. Der Originaltext bleibt erhalten."
        case .empty: "Die KI hat keinen Text zurückgegeben. Der Originaltext bleibt erhalten."
        }
    }
}
