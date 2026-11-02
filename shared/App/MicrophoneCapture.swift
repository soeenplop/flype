import AVFoundation
import Foundation
import Synchronization

/// Counts the audio frames actually received, rather than trusting a recorder's
/// running flag. Close the writer before handing the file to SpeechAnalyzer.
@MainActor
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var writer: AudioFrameWriter?
    private var tapInstalled = false
    private var meterNode: AVAudioSinkNode?
    private let fastMeter = RealtimeInputMeter()

    var isRunning: Bool { engine.isRunning }
    var duration: TimeInterval { writer?.duration ?? 0 }
    var error: Error? { writer?.error }
    var level: Float { meterNode != nil ? fastMeter.level : (writer?.level ?? 0) }
    var meterFrameCount: UInt32 { fastMeter.frameCount }
    var peak: Float { writer?.peak ?? 0 }

    func start(url: URL) throws {
        if engine.isRunning, let writer {
            try writer.begin(url: url)
            return
        }
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
            guard !AVAudioApplication.shared.isInputMuted else { throw CaptureError.muted }
            if let microphone = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try session.setPreferredInput(microphone)
            }
            if session.maximumInputNumberOfChannels >= 1 {
                try session.setPreferredInputNumberOfChannels(1)
            }
        #endif
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
        #if DEBUG && os(iOS)
            let ports = session.currentRoute.inputs.map { $0.portType.rawValue }.joined(separator: ",")
            print(
                "FLYPE_INPUT_FORMAT channels=\(format.channelCount) format=\(format.commonFormat.rawValue) stride=\(format.isInterleaved) gain=\(session.inputGain) ports=\(ports) ioBuffer=\(session.ioBufferDuration)"
            )
        #endif
        if format.commonFormat == .pcmFormatFloat32 {
            let node = Self.makeMeterNode(meter: fastMeter, stride: format.isInterleaved ? Int(format.channelCount) : 1)
            engine.attach(node)
            engine.connect(input, to: node, format: format)
            meterNode = node
        }
        let writer = try AudioFrameWriter(url: url, format: format)
        self.writer = writer
        input.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in
            writer.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    nonisolated private static func makeMeterNode(meter: RealtimeInputMeter, stride: Int) -> AVAudioSinkNode {
        // Construct outside actor isolation: the callback executes on the audio IO thread.
        AVAudioSinkNode { _, frames, buffers in
            meter.measure(frames: frames, buffers: buffers, stride: stride)
            return 0
        }
    }

    func finishSegment() { writer?.close() }

    func stop() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        writer?.close()
    }

    enum CaptureError: LocalizedError {
        case noInput, muted
        var errorDescription: String? {
            switch self {
            case .noInput: "Es ist kein nutzbarer Mikrofoneingang verfügbar."
            case .muted:
                "Der Mikrofoneingang für Flype ist stummgeschaltet. Bitte hebe die Stummschaltung auf und versuche es erneut."
            }
        }
    }
}

/// The audio tap and UI use different threads. All access, including finalization
/// of the CAF header, is serialized and no audio is retained after closing.
private final class AudioFrameWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var writeError: Error?
    private var currentLevel: Float = 0
    private var maximumPeak: Float = 0
    private let sampleRate: Double
    private let format: AVAudioFormat

    init(url: URL, format: AVAudioFormat) throws {
        sampleRate = format.sampleRate
        self.format = format
        file = try AVAudioFile(
            forWriting: url, settings: format.settings,
            commonFormat: format.commonFormat, interleaved: format.isInterleaved)
    }

    func begin(url: URL) throws {
        try lock.withLock {
            file = try AVAudioFile(
                forWriting: url, settings: format.settings,
                commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            frames = 0
            writeError = nil
            currentLevel = 0
            maximumPeak = 0
        }
    }

    var duration: TimeInterval { lock.withLock { Double(frames) / sampleRate } }
    var error: Error? { lock.withLock { writeError } }
    var level: Float { lock.withLock { currentLevel } }
    var peak: Float { lock.withLock { maximumPeak } }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file, writeError == nil else { return }
            do {
                #if DEBUG
                    if frames == 0 { print("FLYPE_FIRST_AUDIO_BUFFER frames=\(buffer.frameLength) rate=\(sampleRate)") }
                #endif
                try file.write(from: buffer)
                frames += AVAudioFramePosition(buffer.frameLength)
                if let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
                    var sum: Float = 0
                    var peak: Float = 0
                    for frame in 0..<Int(buffer.frameLength) {
                        let sample = samples[frame * buffer.stride]
                        sum += sample * sample
                        peak = max(peak, abs(sample))
                    }
                    currentLevel = sqrt(sum / Float(buffer.frameLength))
                    maximumPeak = max(maximumPeak, peak)
                }
            } catch { writeError = error }
        }
    }

    func close() { lock.withLock { file = nil } }
}

/// Audio-thread work is limited to scalar math and lock-free atomic stores.
/// No file access, allocation, dispatch, logging, locks or UI calls in measure().
private final class RealtimeInputMeter: @unchecked Sendable {
    private let rmsBits = Atomic<UInt32>(0)
    private let frames = Atomic<UInt32>(0)
    var level: Float { Float(bitPattern: rmsBits.load(ordering: .relaxed)) }
    var frameCount: UInt32 { frames.load(ordering: .relaxed) }
    func measure(frames frameCount: AVAudioFrameCount, buffers: UnsafePointer<AudioBufferList>, stride: Int) {
        guard buffers.pointee.mNumberBuffers > 0 else { return }
        let buffer = buffers.pointee.mBuffers
        guard let data = buffer.mData, stride > 0 else { return }
        let count = min(Int(frameCount), Int(buffer.mDataByteSize) / (MemoryLayout<Float>.stride * stride))
        guard count > 0 else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        var sum: Float = 0
        for index in 0..<count {
            let sample = samples[index * stride]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        rmsBits.store(rms.bitPattern, ordering: .relaxed)
        frames.store(frameCount, ordering: .relaxed)
    }
}
