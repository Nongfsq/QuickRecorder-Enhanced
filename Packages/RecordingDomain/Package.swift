// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RecordingDomain",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "RecordingDomain", targets: ["RecordingDomain"])
    ],
    targets: [
        .target(name: "RecordingDomain"),
        .testTarget(name: "RecordingDomainTests", dependencies: ["RecordingDomain"])
    ]
)
