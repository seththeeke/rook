// swift-tools-version: 6.0
// RookKit: all non-UI logic for the Rook app. Runs its tests on macOS via `swift test` (no simulator).
import PackageDescription

let package = Package(
    name: "RookKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RookModels", targets: ["RookModels"]),
    ],
    targets: [
        .target(name: "RookModels"),
        .testTarget(
            name: "RookModelsTests",
            dependencies: ["RookModels"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
