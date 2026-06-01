// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EndlessFrontierCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "EndlessFrontierCore",
            targets: ["EndlessFrontierCore"]
        )
    ],
    targets: [
        .target(
            name: "EndlessFrontierCore",
            resources: [
                .copy("Resources/GameData")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "EndlessFrontierCoreTests",
            dependencies: ["EndlessFrontierCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
