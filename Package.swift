// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeLector",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "LectorCore"),
        .executableTarget(name: "ClaudeLector", dependencies: ["LectorCore"]),
        .executableTarget(name: "LectorSpike", dependencies: ["LectorCore"]),
        .testTarget(name: "LectorCoreTests", dependencies: ["LectorCore"]),
    ],
    swiftLanguageModes: [.v6]
)
