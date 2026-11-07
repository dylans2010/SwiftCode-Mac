// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "axdrive",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "axdrive", path: "Sources/axdrive")
    ],
    swiftLanguageModes: [.v5]
)
