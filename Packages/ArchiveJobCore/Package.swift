// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "ArchiveJobCore",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ArchiveJobCore", targets: ["ArchiveJobCore"])
    ],
    targets: [
        .target(name: "ArchiveJobCore"),
        .testTarget(name: "ArchiveJobCoreTests", dependencies: ["ArchiveJobCore"])
    ]
)
