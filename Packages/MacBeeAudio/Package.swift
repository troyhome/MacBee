// swift-tools-version: 5.10
// MacBeeAudio — bit-perfect playback engine for MacBee (Phase 1).

import PackageDescription

let package = Package(
    name: "MacBeeAudio",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacBeeAudio", targets: ["MacBeeAudio"]),
        .executable(name: "macbee-play", targets: ["MacBeePlayCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sbooth/SFBAudioEngine", .upToNextMinor(from: "0.14.0")),
    ],
    targets: [
        .target(
            name: "MacBeeAudio",
            dependencies: [.product(name: "SFBAudioEngine", package: "SFBAudioEngine")]
        ),
        .executableTarget(
            name: "MacBeePlayCLI",
            dependencies: ["MacBeeAudio"]
        ),
        .testTarget(
            name: "MacBeeAudioTests",
            dependencies: ["MacBeeAudio"]
        ),
    ]
)
