// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swiftcode-homekit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HomeKit", targets: ["HomeKit"]),
    ],
    targets: [
        .target(
            name: "HomeKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HomeKitTests",
            dependencies: ["HomeKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
