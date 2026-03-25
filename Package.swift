// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "yalyric",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "yalyricLib",
            path: "Sources",
            exclude: ["App/main.swift"]
        ),
        .executableTarget(
            name: "yalyric",
            dependencies: ["yalyricLib"],
            path: "Executable"
        ),
        .testTarget(
            name: "yalyricTests",
            dependencies: ["yalyricLib"],
            path: "Tests"
        )
    ]
)
