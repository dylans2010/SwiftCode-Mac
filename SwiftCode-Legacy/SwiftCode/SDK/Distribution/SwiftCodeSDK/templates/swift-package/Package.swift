// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftPackageTemplate",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwiftPackageTemplate", targets: ["SwiftPackageTemplate"])],
    targets: [
        .target(name: "SwiftPackageTemplate"),
        .testTarget(name: "SwiftPackageTemplateTests", dependencies: ["SwiftPackageTemplate"])
    ]
)
