// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipHaven",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipHaven", targets: ["ClipHaven"]),
        .library(name: "ClipHavenCore", targets: ["ClipHavenCore"]),
    ],
    targets: [
        .target(name: "ClipHavenCore"),
        .executableTarget(name: "ClipHaven", dependencies: ["ClipHavenCore"]),
        .testTarget(name: "ClipHavenCoreTests", dependencies: ["ClipHavenCore"]),
    ]
)
