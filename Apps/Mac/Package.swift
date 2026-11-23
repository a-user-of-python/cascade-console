// swift-tools-version: 5.9
// Cascade Console — macOS app scaffold (Agent 3).
// Builds as a SwiftPM executable on macOS; the same sources drop unchanged
// into an Xcode macOS App target named "CascadeConsoleMac" (see README.md).
import PackageDescription

let package = Package(
    name: "CascadeConsoleMac",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CascadeConsoleMac",
            path: "CascadeConsoleMac"
        )
    ]
)
