// swift-tools-version: 6.0
import PackageDescription

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
let coreModule = "OpenViewsCore"
let uiModule = "OpenViews"
let renamed: [SwiftSetting] = [.define("OPENVIEWS_RENAMED")]
#else
let coreModule = "SwiftUICore"
let uiModule = "SwiftUI"
let renamed: [SwiftSetting] = []
#endif

let package = Package(
    name: "swiftcode-swiftui",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: uiModule, targets: [uiModule]),
        .library(name: coreModule, targets: [coreModule]),
        .library(name: "OVText", targets: ["OVText"]),
        .library(name: "OVRender", targets: ["OVRender"]),
        .library(name: "OVPlatform", targets: ["OVPlatform"]),
        .library(name: "OVDBus", targets: ["OVDBus"]),
        .library(name: "OVAccessibilityATSPI", targets: ["OVAccessibilityATSPI"]),
        .executable(name: "ov-sample", targets: ["OVSampleApp"]),
        .executable(name: "ov-settings", targets: ["OVSettingsSample"]),
        .executable(name: "ov-mini-ide", targets: ["OVMiniIDE"]),
        .executable(name: "ov-editor-bench", targets: ["OVEditorBench"]),
    ],
    targets: [
        .target(name: "OVText", path: "Sources/OVText", resources: [.copy("Resources/Fonts")]),
        .target(name: "OVRender", dependencies: ["CThorVG", "COVVulkan"], path: "Sources/OVRender"),
        .target(name: "COVVulkan", path: "Sources/COVVulkan", exclude: ["vulkan"], publicHeadersPath: "include",
                linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "CThorVG", path: "Sources/CThorVG",
                exclude: ["thorvg/LICENSE"],
                sources: ["thorvg/src"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("config"),
                    .headerSearchPath("include"),
                    .headerSearchPath("thorvg/inc"),
                    .headerSearchPath("thorvg/src/common"),
                    .headerSearchPath("thorvg/src/renderer"),
                    .headerSearchPath("thorvg/src/renderer/cpu_engine"),
                    .headerSearchPath("thorvg/src/loaders/raw"),
                    .headerSearchPath("thorvg/src/loaders/png"),
                    .headerSearchPath("thorvg/src/loaders/jpg"),
                    .define("TVG_STATIC"),
                ]),
        .target(name: coreModule, dependencies: ["OVText", "OVRender"], path: "Sources/SwiftUICore", swiftSettings: renamed),
        .target(name: "COVSDL", path: "Sources/COVSDL",
                linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "OVPlatform", dependencies: ["COVSDL"], path: "Sources/OVPlatform"),
        .target(name: "OVDBus", path: "Sources/OVDBus"),
        .target(name: "OVAccessibilityATSPI", dependencies: ["OVDBus"], path: "Sources/OVAccessibilityATSPI"),
        .target(name: uiModule, dependencies: [.target(name: coreModule), "OVPlatform", "OVRender", "OVAccessibilityATSPI"],
                path: "Sources/SwiftUI", swiftSettings: renamed),
        .executableTarget(name: "OVSampleApp", dependencies: [.target(name: uiModule), "OVPlatform"],
                          path: "Sources/OVSampleApp", swiftSettings: renamed),
        .executableTarget(name: "OVSettingsSample", dependencies: [.target(name: uiModule), "OVPlatform"],
                          path: "Sources/OVSettingsSample", swiftSettings: renamed),
        .executableTarget(name: "OVMiniIDE", dependencies: [.target(name: uiModule), "OVPlatform"],
                          path: "Sources/OVMiniIDE", swiftSettings: renamed),
        .executableTarget(name: "OVEditorBench", dependencies: [.target(name: uiModule), "OVPlatform"],
                          path: "Sources/OVEditorBench", swiftSettings: renamed),
        .testTarget(name: "OpenViewsTests",
                    dependencies: [.target(name: coreModule), .target(name: uiModule), "OVText", "OVRender",
                                   "OVPlatform", "OVDBus", "OVAccessibilityATSPI"],
                    path: "Tests/OpenViewsTests", exclude: ["R5/Fixtures", "R5/Goldens"], swiftSettings: renamed),
    ],
    cxxLanguageStandard: .cxx14
)
