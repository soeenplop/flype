import CoreML
import FluidAudio
import Foundation

public actor ParakeetRuntime {
    private var inFlight = false
    private var manager: AsrManager?
    private var loadedDirectory: URL?
    public init() {
        AppLogger.minimumLevel = .fault
        AppLogger.mirrorsToConsole = false
    }
    public func prepare(directory: URL) async throws {
        guard !inFlight else { throw CocoaError(.coderInvalidValue) }
        if manager != nil, loadedDirectory == directory { return }
        inFlight = true
        defer { inFlight = false }
        try Task.checkCancellation()
        #if targetEnvironment(simulator)
            // The simulator does not provide the Neural Engine.
            let computeUnits = MLComputeUnits.cpuOnly
        #else
            let computeUnits = MLComputeUnits.cpuAndNeuralEngine
        #endif
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        // Exact local files only: this loader never resolves or downloads a mutable repo.
        let models = try AsrModels.loadLocal(
            from: directory, version: .v3, configuration: configuration,
            encoderPrecision: .int8V2, encoderComputeUnits: computeUnits)
        try Task.checkCancellation()
        let manager = AsrManager()
        try await manager.loadModels(models)
        try Task.checkCancellation()
        self.manager = manager
        loadedDirectory = directory
    }
    public func transcribe(file: URL) async throws -> String {
        guard !inFlight else { throw CocoaError(.coderInvalidValue) }
        guard let manager else { throw CocoaError(.fileReadNoSuchFile) }
        inFlight = true
        defer { inFlight = false }
        try Task.checkCancellation()
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        // SDK converts through AVAudioConverter to 16 kHz mono Float32 and handles long files.
        let result = try await manager.transcribe(file, decoderState: &state)
        try Task.checkCancellation()
        return result.text
    }
    public func unload() async throws {
        guard !inFlight else { throw CocoaError(.userCancelled) }
        inFlight = true
        defer { inFlight = false }
        await manager?.cleanup()
        manager = nil
        loadedDirectory = nil
    }
}
