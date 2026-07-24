// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RNNoiseProcessor",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "RNNoiseProcessor", targets: ["RNNoiseProcessor"])
    ],
    targets: [
        .target(
            name: "CRNNoise",
            path: "Sources/CRNNoise",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("USE_WEIGHTS_FILE")
            ]
        ),
        .target(
            name: "RNNoiseProcessor",
            dependencies: ["CRNNoise"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RNNoiseProcessorTests",
            dependencies: ["RNNoiseProcessor"]
        )
    ]
)
