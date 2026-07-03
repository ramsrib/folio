// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Folio",
            path: "Sources/Folio",
            // Relaxed concurrency for the MVP; tighten to .v6 once the
            // file/index/editor boundaries settle.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
