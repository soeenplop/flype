import AVFoundation
import FlypeCore
import Foundation
import Speech

/// Secondary on-device recognizer. Its output is evidence for bounded
/// dictionary edits only and never replaces the selected engine's transcript.
actor DictionaryAudioVerifier {
    private var locale: Locale?

    func prepare(language: FlypeLanguage = .de) async throws {
        guard
            let locale = await DictationTranscriber.supportedLocale(
                equivalentTo: Locale(identifier: language.localeIdentifier))
        else {
            throw RecognitionError.unavailable
        }
        let module = DictationTranscriber(locale: locale, preset: .longDictation)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
        self.locale = locale
    }

    func verify(file: URL, terms: [String]) async throws -> String {
        guard let locale, !terms.isEmpty else { throw RecognitionError.unavailable }
        let module = DictationTranscriber(locale: locale, preset: .longDictation)
        let analyzer = SpeechAnalyzer(modules: [module])
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(Set(terms)).sorted()
        try await analyzer.setContext(context)
        let collector = Task {
            var text = ""
            for try await result in module.results { text += String(result.text.characters) }
            return text
        }
        defer { collector.cancel() }
        return try await withTaskCancellationHandler {
            try await analyzer.start(inputAudioFile: AVAudioFile(forReading: file), finishAfterFile: true)
            let text = try await collector.value
            try Task.checkCancellation()
            return text
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

}
