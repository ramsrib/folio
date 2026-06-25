// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Slate",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Slate",
            path: "Sources/Slate",
            // Relaxed concurrency for the MVP; tighten to .v6 once the
            // file/index/editor boundaries settle.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
