// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "FlypeSpeech", platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "FlypeSpeech", targets: ["FlypeSpeech"])],
    dependencies: [.package(path: "../../vendor/FluidAudio")],
    targets: [.target(name: "FlypeSpeech", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
              .executableTarget(name: "FlypeSpeechCheck", dependencies: ["FlypeSpeech"])]
)
