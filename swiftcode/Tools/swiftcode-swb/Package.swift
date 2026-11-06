// swift-tools-version: 6.0
// swiftcode-swb: a small helper that talks to swift-build's build service as a
// library, for queries its `swbuild` command line does not offer (exported
// build settings). It is a separate package so that the SwiftCode package itself
// takes no dependency on swift-build. See specs/xcodebuild/show-build-settings.md.
//
//     swift build --product swiftcode-swb
//     swift build --product SWBBuildServiceBundle
//
// swiftcodebuild finds the helper through SWIFTCODE_SWB, then PATH, then next to
// itself. The pinned revision is the head of swift-build's release/6.4.x
// branch: its exported settings matched the reference tool exactly on the
// test corpus, while main exports 16 newer settings (see
// specs/xcodebuild/show-build-settings.md §6).
import PackageDescription

let package = Package(
    name: "swiftcode-swb",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-build", revision: "5d44ed6ba16c53d56cac5fc6a2d572635aa4a979"),
    ],
    targets: [
        // Sources/SwiftCodeSigning is a symbolic link to swiftcode/Sources/SwiftCodeSigning
        // (Foundation only): the signing logic is tested in the SwiftCode package.
        .target(name: "SwiftCodeSigning"),
        // Sources/SwiftCodeRelease is a link to swiftcode/Sources/SwiftCodeRelease, the release's version.
        .target(name: "SwiftCodeRelease"),
        .executableTarget(name: "swiftcode-swb", dependencies: [.product(name: "SwiftBuild", package: "swift-build"), "SwiftCodeSigning", "SwiftCodeRelease"]),
    ]
)
