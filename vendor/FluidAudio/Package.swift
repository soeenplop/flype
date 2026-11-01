// swift-tools-version: 6.2
import PackageDescription
// Source-only ASR/VAD build of FluidAudio v0.18.2, e396cf780c4abf8e395087467c0585d3b0d17f68.
// Upstream optional TTS/diarization/NeMo binary targets are intentionally absent.
let package = Package(
    name: "FluidAudio", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FluidAudio", targets: ["FluidAudio"])],
    targets: [
        .target(name: "FluidAudio", dependencies: ["FastClusterWrapper", "MachTaskSelfWrapper"],
                path: "Sources/FluidAudio", exclude: ["ASR/Parakeet/Unified/benchmark.md"]),
        .target(name: "FastClusterWrapper", path: "Sources/FastClusterWrapper", publicHeadersPath: "include"),
        .target(name: "MachTaskSelfWrapper", path: "Sources/MachTaskSelfWrapper", publicHeadersPath: "include")
    ], cxxLanguageStandard: .cxx17
)
