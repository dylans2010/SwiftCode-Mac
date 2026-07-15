// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftCode",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SwiftCode", targets: ["SwiftCode"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", upToNextMajorVersion: "0.9.0"),
        .package(url: "https://github.com/JohnSundell/Splash.git", upToNextMajorVersion: "0.16.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", upToNextMajorVersion: "0.31.0"),
        .package(url: "https://github.com/apple/swift-markdown.git", upToNextMajorVersion: "0.2.0"),
        .package(url: "https://github.com/timi2506/WelcomeView.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "SwiftCode",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "WelcomeView", package: "WelcomeView")
            ],
            path: "SwiftCode"
        )
    ]
)
