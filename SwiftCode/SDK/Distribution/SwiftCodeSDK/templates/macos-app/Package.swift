// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSAppTemplate",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacOSAppTemplate", targets: ["MacOSAppTemplate"])],
    targets: [.executableTarget(name: "MacOSAppTemplate")]
)
