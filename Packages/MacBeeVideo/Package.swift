// swift-tools-version: 5.10
// MacBeeVideo — the Videos section: finds movies, TV shows and music videos in video folders,
// and plays them (MKV and nearly every other format) with libmpv through MPVKit.

import PackageDescription

let package = Package(
    name: "MacBeeVideo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacBeeVideo", targets: ["MacBeeVideo"]),
    ],
    dependencies: [
        // LGPL build of mpv + FFmpeg. Pinned exactly: MPVKit's binaries change between releases.
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "1.1.0-n9.0.2"),
    ],
    targets: [
        .target(
            name: "MacBeeVideo",
            dependencies: [.product(name: "MPVKit", package: "MPVKit")]
        ),
        .testTarget(
            name: "MacBeeVideoTests",
            dependencies: ["MacBeeVideo"]
        ),
    ]
)
