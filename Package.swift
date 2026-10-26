// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhotoVault",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PhotoVault",
            path: "Sources/PhotoVault",
            linkerSettings: [
                .linkedFramework("ImageCaptureCore"),
                // Embed Info.plist so macOS shows the right name and privacy prompts
                // when the app is run straight from `swift run`.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Support/Info.plist",
                ]),
            ]
        ),
    ]
)
