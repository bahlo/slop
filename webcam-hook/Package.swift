// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "webcam-hook",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "webcam-hook",
            path: "Sources/webcam-hook",
            linkerSettings: [
                // Embed an Info.plist so macOS can identify the binary for
                // Local Network privacy (bundle ID + usage description).
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(Context.packageDirectory)/Support/Info.plist",
                ]),
            ]
        ),
    ]
)
