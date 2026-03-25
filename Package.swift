// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LyricSync",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LyricSync",
            path: "Sources"
        )
    ]
)
