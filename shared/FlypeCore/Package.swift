// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlypeCore",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [.library(name: "FlypeCore", targets: ["FlypeCore"])],
    targets: [
        .target(name: "FlypeCore"),
        .testTarget(name: "FlypeCoreTests", dependencies: ["FlypeCore"]),
    ]
)
