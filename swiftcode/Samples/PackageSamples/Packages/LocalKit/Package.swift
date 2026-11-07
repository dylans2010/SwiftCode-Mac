// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LocalKit", targets: ["LocalKit"]),
        .library(name: "LocalKitDynamic", type: .dynamic, targets: ["LocalKitDynamicCore"]),
    ],
    targets: [
        .target(name: "LocalKit", resources: [.process("Resources")]),
        .target(name: "LocalKitDynamicCore"),
    ]
)
