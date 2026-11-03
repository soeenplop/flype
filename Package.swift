// swift-tools-version: 6.2
import PackageDescription

// Builds the Mac app. SwiftPM only compiles sources inside the package root, and the Mac target shares
// shared/App with the iOS Xcode target, so this manifest has to live at the repository root.
let package = Package(
    name: "Flype",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Flype", targets: ["FlypeMac"])],
    dependencies: [
        .package(path: "shared/FlypeCore"),
        .package(path: "shared/FlypeSpeech"),
    ],
    targets: [
        .executableTarget(
            name: "FlypeMac",
            dependencies: [
                .product(name: "FlypeCore", package: "FlypeCore"),
                .product(name: "FlypeSpeech", package: "FlypeSpeech"),
            ],
            path: ".",
            // SwiftPM scans the whole target path for resources, even when `sources` is set.
            exclude: [
                "build", "docs", "ios", "macos/scripts", "macos/README.md", "macos/Flype.entitlements",
                "macos/Flype-AppStore.entitlements", "scripts", "shared/Config", "shared/FlypeCore",
                "shared/FlypeSpeech", "shared/README.md", "shared/Resources", "supabase", "vendor", "website",
                "CONTRIBUTING.md", "README.md",
            ],
            sources: ["macos/App", "shared/App"],
            swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
