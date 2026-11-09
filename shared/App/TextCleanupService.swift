import FlypeCore
import Foundation
import os

/// Logs how long each step after the recording took, as durations only and never with text.
/// Read it in Console.app with the category "timing".
struct DictationTiming {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "flype", category: "timing")
    private var last = ContinuousClock.now
    private var steps: [String] = []
    private var total = Duration.zero

    mutating func mark(_ step: String) {
        let now = ContinuousClock.now
        let duration = last.duration(to: now)
        steps.append("\(step)=\(duration.milliseconds)ms")
        total += duration
        last = now
    }

    mutating func report(_ step: String, characters: Int) {
        mark(step)
        let steps = steps.joined(separator: " ")
        let total = total.milliseconds
        Self.log.info("dictation \(steps, privacy: .public) total=\(total)ms characters=\(characters)")
    }
}

extension Duration {
    fileprivate var milliseconds: Int64 { components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000 }
}

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
