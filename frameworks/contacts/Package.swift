// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swiftcode-contacts",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Contacts", targets: ["Contacts"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "Contacts",
            dependencies: ["CSQLite"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ContactsTests",
            dependencies: ["Contacts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
