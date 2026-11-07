// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swiftcode-swb",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-build", revision: "5d44ed6ba16c53d56cac5fc6a2d572635aa4a979"),
    ],
    targets: [
        .target(name: "SwiftCodeSigning"),
        .target(name: "SwiftCodeRelease"),
        .executableTarget(name: "swiftcode-swb", dependencies: [.product(name: "SwiftBuild", package: "swift-build"), "SwiftCodeSigning", "SwiftCodeRelease"]),
    ]
)
