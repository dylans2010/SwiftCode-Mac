// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "swiftcode-healthkit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HealthKit", targets: ["HealthKit"]),
    ],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "HealthKit", dependencies: ["CSQLite"], path: "Sources/HealthKit"),
        .testTarget(name: "HealthKitTests", dependencies: ["HealthKit"], path: "Tests/HealthKitTests"),
    ]
)
