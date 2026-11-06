// swift-tools-version:6.0
//
// swiftcode-scene-composer: the platform-neutral core of the SwiftCode Scene
// Composer, a scene editor for RealityKit content (USD scenes and, later,
// Reality Composer Pro-compatible projects) that runs on Linux and macOS.
// Clean-room code under AGENTS.md: built from public USD/MaterialX sources and
// from specs/tools/scene-composer/ only.
//
// SceneComposerCore: the document model (prim tree, transforms, selection,
// undoable commands, clipboard, generic components).
// SceneComposerCLI + swiftcode-scene: the command-line tool.
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
