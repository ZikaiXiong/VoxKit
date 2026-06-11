// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VoxKit",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoxKit",
            path: "Sources/VoxKit"
        )
    ],
    swiftLanguageVersions: [.v5]
)
