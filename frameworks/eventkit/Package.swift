// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swiftcode-eventkit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EventKit", targets: ["EventKit"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "EventKit",
            dependencies: ["CSQLite"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EventKitTests",
            dependencies: ["EventKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
