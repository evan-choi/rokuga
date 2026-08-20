// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RokugaCore",
    defaultLocalization: "en",
    platforms: [
        .macOS("13.3")
    ],
    products: [
        .executable(name: "rokuga-bench", targets: ["rokuga-bench"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
        .library(name: "EncoderKit", targets: ["EncoderKit"]),
        .library(name: "TrimKit", targets: ["TrimKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"])
    ],
    targets: [
        // MARK: Capture — ScreenCaptureKit session management, recording state machine

        .target(
            name: "CaptureKit",
            dependencies: ["EncoderKit", "SettingsKit"]
        ),

        // MARK: Encode — AVAssetWriter/VideoToolbox pipeline, audio mixing

        .target(
            name: "EncoderKit",
            dependencies: ["SettingsKit"]
        ),

        // MARK: Trim — passthrough export, timeline model

        .target(
            name: "TrimKit",
            dependencies: ["SettingsKit"]
        ),

        // MARK: Settings — UserDefaults-backed preferences, shared model types

        .target(
            name: "SettingsKit"
        ),
        .testTarget(
            name: "EncoderKitTests",
            dependencies: ["EncoderKit"]
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit"]
        ),
        .testTarget(
            name: "SettingsKitTests",
            dependencies: ["SettingsKit"]
        ),
        .testTarget(
            name: "TrimKitTests",
            dependencies: ["TrimKit"]
        ),
        .executableTarget(
            name: "rokuga-bench",
            dependencies: ["EncoderKit", "TrimKit"]
        )
    ]
)
