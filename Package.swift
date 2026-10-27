// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaShelf",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MediaShelfCore", targets: ["MediaShelfCore"]),
        .executable(name: "mediashelf-cli", targets: ["MediaShelfCLI"]),
    ],
    targets: [
        .target(
            name: "MediaShelfCore",
            path: "Sources/MediaShelfCore"
        ),
        .executableTarget(
            name: "MediaShelfCLI",
            dependencies: ["MediaShelfCore"],
            path: "Sources/MediaShelfCLI"
        ),
        .testTarget(
            name: "MediaShelfCoreTests",
            dependencies: ["MediaShelfCore"],
            path: "Tests/MediaShelfCoreTests"
        ),
    ]
)
