import AVFoundation
import FlypeCore
import FlypeSpeech
import Foundation
import Speech

protocol SpeechRecognitionEngine: Actor {
    func prepare() async throws
    func transcribe(file: URL) async throws -> String
    func cancel() async
}

actor AppleSpeechEngine: SpeechRecognitionEngine {
    /// The simulator lists languages for DictationTranscriber, but has no assets to run them.
    static func isAvailable(language: FlypeLanguage) async -> Bool {
        #if targetEnvironment(simulator)
            return false
        #else
            let locale = Locale(identifier: language.localeIdentifier)
            if SpeechTranscriber.isAvailable, await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil {
                return true
            }
            return await DictationTranscriber.supportedLocale(equivalentTo: locale) != nil
        #endif
    }
    private let language: FlypeLanguage
    init(language: FlypeLanguage = .de) { self.language = language }
    private var transcriber: SpeechTranscriber?
    private var fallback: DictationTranscriber?
    private var analyzer: SpeechAnalyzer?
    func prepare() async throws {
        transcriber = nil
        fallback = nil
        let locale = Locale(identifier: language.localeIdentifier)
        let module: any SpeechModule
        if SpeechTranscriber.isAvailable, let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        {
            let value = SpeechTranscriber(locale: supported, preset: .transcription)
            transcriber = value
            module = value
        } else if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let value = DictationTranscriber(locale: supported, preset: .longDictation)
            fallback = value
            module = value
        } else {
            throw RecognitionError.unavailable
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
        try Task.checkCancellation()
    }
    func transcribe(file: URL) async throws -> String {
        let transcriber = self.transcriber
        let fallback = self.fallback
        let module: any SpeechModule
        if let transcriber {
            module = transcriber
        } else if let fallback {
            module = fallback
        } else {
            throw RecognitionError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        let collector = Task {
            var text = ""
            if let transcriber {
                for try await result in transcriber.results { text += String(result.text.characters) }
            } else if let fallback {
                for try await result in fallback.results { text += String(result.text.characters) }
            }
            return text
        }
        defer {
            collector.cancel()
            self.analyzer = nil
            self.transcriber = nil
            self.fallback = nil
        }
        try await analyzer.start(inputAudioFile: AVAudioFile(forReading: file), finishAfterFile: true)
        let text = try await collector.value
        try Task.checkCancellation()
        return text
    }
    func cancel() async {
        let current = analyzer
        analyzer = nil
        transcriber = nil
        fallback = nil
        await current?.cancelAndFinishNow()
    }
}
actor ParakeetSpeechEngine: SpeechRecognitionEngine {
    static let runtime = ParakeetRuntime()
    func prepare() async throws {
        let directory = try await ParakeetModelStore.shared.installedDirectory()
        try await Self.runtime.prepare(directory: directory)
    }
    func transcribe(file: URL) async throws -> String { try await Self.runtime.transcribe(file: file) }
    func cancel() async {
        // Cancellation propagates through the task; results are operation-ID guarded.
    }
    static func unload() async throws { try await runtime.unload() }
}
enum RecognitionError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Das ausgewählte lokale Sprachmodell ist momentan nicht verfügbar." }
}
