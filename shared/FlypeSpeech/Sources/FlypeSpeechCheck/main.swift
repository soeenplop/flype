import AVFoundation
import FlypeSpeech
import Foundation

@main
struct SpeechCheck {
    static func main() async throws {
        guard CommandLine.arguments.count >= 3 else {
            print("Usage: FlypeSpeechCheck MODEL_DIRECTORY AUDIO_FILE [REPETITIONS]")
            return
        }
        let runtime = ParakeetRuntime()
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        var audio = URL(fileURLWithPath: CommandLine.arguments[2])
        let repetitions = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 1 : 1
        let repeated = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: repeated) }
        if repetitions > 1 {
            let input = try AVAudioFile(forReading: audio)
            let output = try AVAudioFile(forWriting: repeated, settings: input.processingFormat.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 16_000)!
            for _ in 0..<min(repetitions, 30) {
                input.framePosition = 0
                while input.framePosition < input.length {
                    try input.read(into: buffer)
                    try output.write(from: buffer)
                }
            }
            audio = repeated
        }
        let input = try AVAudioFile(forReading: audio)
        print("AUDIO seconds=\(Double(input.length) / input.processingFormat.sampleRate)")
        let start = ProcessInfo.processInfo.systemUptime
        try await runtime.prepare(directory: directory)
        print("MODEL_PREPARED seconds=\(ProcessInfo.processInfo.systemUptime - start)")
        for iteration in 0..<2 {
            let begin = ProcessInfo.processInfo.systemUptime
            let text = try await runtime.transcribe(file: audio)
            print(
                "TRANSCRIPTION iteration=\(iteration) characters=\(text.count) seconds=\(ProcessInfo.processInfo.systemUptime - begin)"
            )
        }
        try await runtime.unload()
    }
}
