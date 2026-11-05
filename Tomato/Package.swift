// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tomato",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "TomatoCore"),
        .executableTarget(
            name: "Tomato",
            dependencies: ["TomatoCore"],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "TomatoCoreTests", dependencies: ["TomatoCore"]),
    ]
)
