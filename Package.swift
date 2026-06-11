// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoxNote",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoxNote",
            path: "Sources/VoxNote"
        )
    ],
    swiftLanguageVersions: [.v5]
)
