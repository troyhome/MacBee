// swift-tools-version: 5.10
// MacBeeLibrary — music library: scanning, database, artwork, folder monitoring (Phase 2).

import PackageDescription

let package = Package(
    name: "MacBeeLibrary",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacBeeLibrary", targets: ["MacBeeLibrary"]),
        .executable(name: "macbee-library", targets: ["MacBeeLibraryCLI"]),
    ],
    dependencies: [
        .package(path: "../MacBeeAudio"),
        .package(url: "https://github.com/sbooth/SFBAudioEngine", .upToNextMinor(from: "0.14.0")),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    ],
    targets: [
        .target(
            name: "MacBeeLibrary",
            dependencies: [
                .product(name: "MacBeeAudio", package: "MacBeeAudio"),
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "MacBeeLibraryCLI",
            dependencies: ["MacBeeLibrary"]
        ),
        .testTarget(
            name: "MacBeeLibraryTests",
            dependencies: ["MacBeeLibrary", .product(name: "SFBAudioEngine", package: "SFBAudioEngine")]
        ),
    ]
)
