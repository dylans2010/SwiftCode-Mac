// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftcode-storekit",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "StoreKitConfiguration", targets: ["StoreKitConfiguration"]),
        .library(name: "StoreKitEngine", targets: ["StoreKitEngine"]),
        .library(name: "StoreKitSigning", targets: ["StoreKitSigning"]),
        .library(name: "StoreKit", targets: ["StoreKit"]),
        .library(name: "StoreKitTest", targets: ["StoreKitTest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2")
    ],
    targets: [
        .target(name: "StoreKitConfiguration", path: "Sources/StoreKitConfiguration"),
        .target(
            name: "StoreKitEngine",
            dependencies: ["StoreKitConfiguration"],
            path: "Sources/StoreKitEngine"
        ),
        .target(
            name: "StoreKitSigning",
            dependencies: [
                "StoreKitConfiguration", "StoreKitEngine",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/StoreKitSigning"
        ),
        .target(
            name: "StoreKit",
            dependencies: ["StoreKitConfiguration", "StoreKitEngine", "StoreKitSigning"],
            path: "Sources/StoreKit"
        ),
        .target(
            name: "StoreKitTest",
            dependencies: ["StoreKit", "StoreKitConfiguration", "StoreKitEngine"],
            path: "Sources/StoreKitTest"
        ),
        .testTarget(
            name: "StoreKitConfigurationTests",
            dependencies: ["StoreKitConfiguration"],
            path: "Tests/StoreKitConfigurationTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "StoreKitEngineTests",
            dependencies: ["StoreKitEngine", "StoreKitConfiguration"],
            path: "Tests/StoreKitEngineTests"
        ),
        .testTarget(
            name: "StoreKitSigningTests",
            dependencies: [
                "StoreKitSigning", "StoreKitEngine", "StoreKitConfiguration",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Tests/StoreKitSigningTests"
        ),
        .testTarget(
            name: "StoreKitAPITests",
            dependencies: ["StoreKit", "StoreKitTest", "StoreKitEngine", "StoreKitSigning", "StoreKitConfiguration"],
            path: "Tests/StoreKitAPITests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
