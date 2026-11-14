// swift-tools-version: 6.0
// RookKit: all non-UI logic for the Rook app. Runs its tests on macOS via `swift test` (no simulator).
import PackageDescription

let package = Package(
    name: "RookKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RookModels", targets: ["RookModels"]),
        .library(name: "RookFormatting", targets: ["RookFormatting"]),
        .library(name: "RookNetworking", targets: ["RookNetworking"]),
        .library(name: "RookSession", targets: ["RookSession"]),
        .library(name: "RookAuth", targets: ["RookAuth"]),
        .library(name: "RookFeatures", targets: ["RookFeatures"]),
    ],
    targets: [
        .target(name: "RookModels"),
        .testTarget(
            name: "RookModelsTests",
            dependencies: ["RookModels"],
            resources: [.copy("Fixtures")]
        ),

        .target(name: "RookFormatting", dependencies: ["RookModels"]),
        .testTarget(name: "RookFormattingTests", dependencies: ["RookFormatting", "RookModels"]),

        .target(name: "RookNetworking", dependencies: ["RookModels"]),
        .testTarget(name: "RookNetworkingTests", dependencies: ["RookNetworking", "RookModels"]),

        .target(name: "RookSession", dependencies: ["RookModels"]),
        .testTarget(name: "RookSessionTests", dependencies: ["RookSession", "RookModels"]),

        .target(name: "RookAuth", dependencies: ["RookNetworking"]),
        .testTarget(name: "RookAuthTests", dependencies: ["RookAuth"]),

        .target(
            name: "RookFeatures",
            dependencies: ["RookModels", "RookNetworking", "RookAuth", "RookSession", "RookFormatting"]
        ),
        .testTarget(
            name: "RookFeaturesTests",
            dependencies: ["RookFeatures", "RookModels", "RookNetworking", "RookAuth", "RookSession", "RookFormatting"]
        ),
    ]
)
