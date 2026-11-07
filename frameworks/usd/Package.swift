// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftcode-usd",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "USDCore", targets: ["USDCore"]),
        .library(name: "USDStage", targets: ["USDStage"]),
        .library(name: "USDShade", targets: ["USDShade"]),
    ],
    targets: [
        .target(name: "USDCore", path: "Sources/USDCore"),
        .target(name: "USDStage", dependencies: ["USDCore"], path: "Sources/USDStage"),
        .target(
            name: "USDShade",
            dependencies: ["USDCore", "USDStage"],
            path: "Sources/USDShade",
            resources: [.copy("Resources/MaterialX")]
        ),
        .testTarget(
            name: "USDCoreTests",
            dependencies: ["USDCore"],
            path: "Tests/USDCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "USDStageTests", dependencies: ["USDCore", "USDStage"], path: "Tests/USDStageTests"),
        .testTarget(name: "USDShadeTests", dependencies: ["USDCore", "USDStage", "USDShade"], path: "Tests/USDShadeTests"),
    ]
)
