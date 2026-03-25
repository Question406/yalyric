// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LyricSync",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "LyricSyncLib",
            path: "Sources",
            exclude: ["App/main.swift"]
        ),
        .executableTarget(
            name: "LyricSync",
            dependencies: ["LyricSyncLib"],
            path: "Executable"
        ),
        .testTarget(
            name: "LyricSyncTests",
            dependencies: ["LyricSyncLib"],
            path: "Tests"
        )
    ]
)
