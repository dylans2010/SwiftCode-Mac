// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "wincap",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "wincap", path: "Sources/wincap")
    ],
    swiftLanguageModes: [.v5]
)
