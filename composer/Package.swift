// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftcode-scene-composer",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SceneComposerCore", targets: ["SceneComposerCore"]),
        .library(name: "SceneComposerCLI", targets: ["SceneComposerCLI"]),
        .executable(name: "swiftcode-scene", targets: ["swiftcode-scene"]),
    ],
    dependencies: [
        .package(name: "swiftcode-usd", path: "../frameworks/usd"),
    ],
    targets: [
        .target(
            name: "SceneComposerCore",
            dependencies: [
                .product(name: "USDCore", package: "swiftcode-usd"),
                .product(name: "USDStage", package: "swiftcode-usd"),
                .product(name: "USDShade", package: "swiftcode-usd"),
            ],
            resources: [.copy("Resources/components.json")]
        ),
        .target(name: "SceneComposerCLI", dependencies: ["SceneComposerCore"]),
        .executableTarget(name: "swiftcode-scene", dependencies: ["SceneComposerCLI"]),
        .testTarget(name: "SceneComposerCoreTests", dependencies: ["SceneComposerCore"]),
        .testTarget(name: "SceneComposerCLITests", dependencies: ["SceneComposerCLI", "SceneComposerCore"]),
    ]
)
