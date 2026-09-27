// swift-tools-version:5.9
//
// Swift Package manifest. Lets the app build with just the Xcode Command Line
// Tools (`swift build`) — `Scripts/build-app.sh` wraps the binary into a real
// `CricketScore.app`. With full Xcode installed you can instead open
// `CricketScore.xcodeproj` (or this Package.swift) directly.

import PackageDescription

let package = Package(
    name: "CricketScore",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CricketScore",
            path: "CricketScore",
            exclude: ["Resources"]
        )
    ]
)
