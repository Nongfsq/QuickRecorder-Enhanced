// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WindowPlacementCore",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "WindowPlacementCore", targets: ["WindowPlacementCore"])
    ],
    targets: [
        .target(name: "WindowPlacementCore"),
        .testTarget(name: "WindowPlacementCoreTests", dependencies: ["WindowPlacementCore"])
    ]
)
