// swift-tools-version: 5.9
// ABOUTME: SPM package definition for the fade image slideshow app.
// ABOUTME: Declares macOS 13+ target and swift-argument-parser dependency.

import PackageDescription

let package = Package(
    name: "fade",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "fade",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"
        ),
    ]
)
