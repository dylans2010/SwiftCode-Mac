// swift-tools-version: 6.0
import Foundation
import PackageDescription

let package = Package(
    name: "Ycode",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "YcodePlist", targets: ["YcodePlist"]),
        .library(name: "YcodeProject", targets: ["YcodeProject"]),
        .library(name: "YcodeWorkspace", targets: ["YcodeWorkspace"]),
        .library(name: "YcodeSettings", targets: ["YcodeSettings"]),
        .library(name: "YcodeMachO", targets: ["YcodeMachO"]),
        .library(name: "YcodeDarwinABI", targets: ["YcodeDarwinABI"]),
        .library(name: "YcodeDarwinKernel", targets: ["YcodeDarwinKernel"]),
        .library(name: "YcodeXPC", targets: ["YcodeXPC"]),
        .library(name: "YcodeSimFeatures", targets: ["YcodeSimFeatures"]),
        .executable(name: "ycode-simd", targets: ["ycode-simd"]),
        .executable(name: "ycode", targets: ["ycode"]),
        .library(name: "YcodeBuild", targets: ["YcodeBuild"]),
        .library(name: "YcodeDebug", targets: ["YcodeDebug"]),
        .library(name: "YcodeLanguage", targets: ["YcodeLanguage"]),
        .library(name: "YcodeSubprocess", targets: ["YcodeSubprocess"]),
        .library(name: "YcodeAssistant", targets: ["YcodeAssistant"]),
        .library(name: "YcodeCompletion", targets: ["YcodeCompletion"]),
        // Gauge, the profiler (specs/ide/profiler.md): trace format, analysis, Linux recording
        .library(name: "YcodeProfiler", targets: ["YcodeProfiler"]),
        // Gauge's in-process sampler for Linux processes (LD_PRELOAD; profiler.md §3.2)
        .library(name: "YcodeGaugeAgent", type: .dynamic, targets: ["CYcodeGaugeAgent"]),
        .library(name: "YcodePreviews", targets: ["YcodePreviews"]),
        // Legacy libraries & tools
        .library(name: "SwiftCodeGitHub", targets: ["SwiftCodeGitHub"]),
        .library(name: "SwiftCodeExtensions", targets: ["SwiftCodeExtensions"]),
        .library(name: "SwiftCodeCloud", targets: ["SwiftCodeCloud"]),
        .library(name: "SwiftCodePaywall", targets: ["SwiftCodePaywall"]),
        .library(name: "SwiftCodeSDK", targets: ["SwiftCodeSDK"]),
        .library(name: "SwiftCodeSDKStudio", targets: ["SwiftCodeSDKStudio"]),
        .executable(name: "swiftcode-sdk", targets: ["SwiftCodeSDKCLI"]),
        .executable(name: "project-generator", targets: ["SwiftCodeSDKProjectGenerator"]),
        .executable(name: "project-inspector", targets: ["SwiftCodeSDKProjectInspector"]),
        .executable(name: "extension-validator", targets: ["SwiftCodeSDKExtensionValidator"]),
        .executable(name: "diagnostics", targets: ["SwiftCodeSDKDiagnostics"]),
        .executable(name: "documentation-indexer", targets: ["SwiftCodeSDKDocumentationIndexer"]),
        .library(name: "SwiftCodeConnect", targets: ["SwiftCodeConnect"]),
        .library(name: "SwiftCodeCollaboration", targets: ["SwiftCodeCollaboration"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(name: "YcodePlist"),
        .target(name: "YcodeProject", dependencies: ["YcodePlist"]),
        .target(name: "YcodeWorkspace", dependencies: ["YcodeProject"]),
        .target(name: "YcodeSettings", dependencies: ["YcodeProject"]),
        .target(name: "YcodeMachO"),
        // Gauge (specs/ide/profiler.md)
        .target(name: "CYcodeGauge"),
        .target(name: "CYcodeGaugeAgent"),
        .target(name: "YcodeProfiler", dependencies: ["YcodeMachO", "CYcodeGauge"]),
        .testTarget(name: "YcodeProfilerTests", dependencies: ["YcodeProfiler", "YcodeMachO"]),
        // Simulator stage 2 (specs/simulator/vm-shim-protocol.md)
        .target(name: "YcodeDarwinABI"),
        .target(name: "YcodeDarwinKernel", dependencies: ["YcodeDarwinABI"]),
        .target(name: "YcodeXPC"),
        // Host services the VMM offers the guest (stage 7: IOSurface)
        .target(name: "YcodeHostServices", dependencies: ["YcodeDarwinABI", "YcodeDarwinKernel", "YcodeXPC", "CYcodeCamera", "YcodeDisplayStream"]),
        // The host camera layer's V4L2 access, JPEG decoder and pixel conversion (specs/simulator/camera-host.md)
        .target(name: "CYcodeCamera", linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
        // Stage 8a (specs/simulator/stage8-contract.md §5): the Metal host service and its Vulkan back end
        .target(name: "YcodeMetalHost", dependencies: ["YcodeXPC", "YcodeDarwinKernel"]),
        .target(name: "CVulkan"),
        .target(name: "YcodeVulkan", dependencies: ["CVulkan", "YcodeMetalHost"], exclude: ["shaders"]),
        .target(name: "CKVM"),
        .target(name: "YcodeHypervisor", dependencies: ["CKVM", "YcodeDarwinABI"]),
        // The live display stream and viewer input (specs/simulator/display-stream.md)
        .target(name: "CYcodeCodec", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        // Low-latency H.264 through NVIDIA's NVENC / NVDEC, opened at run time (display-stream.md §14)
        .target(name: "CYcodeVideo", exclude: ["nvheaders/ffnvcodec/README.md"], cSettings: [.headerSearchPath("nvheaders")], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "YcodeDisplayStream"),
        // The simulator's settings features (specs/simulator/simulator-features.md, "Ycode implementation")
        .target(name: "YcodeSimFeatures"),
        .testTarget(name: "YcodeSimFeaturesTests", dependencies: ["YcodeSimFeatures"]),
        // Shut-down edits of a device's HealthKit store: grants and seeded samples (specs/simulator/health-simulation.md, "Ycode implementation")
        .systemLibrary(name: "CSQLite"),
        .target(name: "YcodeHealthStore", dependencies: ["CSQLite", "YcodeSimFeatures"]),
        .testTarget(name: "YcodeHealthStoreTests", dependencies: ["YcodeHealthStore", "YcodeSimFeatures"]),
        // The device windows' model: frames, zoom, the hub's sidebar, commands (specs/ide/device-hub.md, "Ycode implementation")
        .target(name: "YcodeDeviceModel"),
        .testTarget(name: "YcodeDeviceModelTests", dependencies: ["YcodeDeviceModel"]),
        .executableTarget(name: "ycode-simd", dependencies: ["YcodeRelease", "YcodeHypervisor", "YcodeDarwinABI", "YcodeDarwinKernel", "YcodeMachO", "YcodeXPC", "YcodeHostServices", "YcodeMetalHost", "YcodeVulkan", "YcodeDisplayStream", "CYcodeCodec", "CYcodeVideo", "YcodeSimFeatures", "YcodeHealthStore", "YcodeProfiler", "YcodeDebug", "YcodeXRReprojection"]),
        .executableTarget(name: "ycode", dependencies: ["YcodeRelease", "YcodePlist", "YcodeProject", "YcodeWorkspace", "YcodeSettings", "YcodeMachO", "YcodeBuild", "YcodeDebug", "YcodePreviews", "YcodeProfiler", "YcodeBuildServer", "YcodeXcodebuild", "YcodeAssetCatalog", "YcodeIDECore", "YcodeStrings", "YcodeSimLink", "YcodeCompletion"]),
        // Subprocess invocation (specs/ide/subprocess.md)
        .target(name: "YcodeSubprocess"),
        .testTarget(name: "YcodeSubprocessTests", dependencies: ["YcodeSubprocess"]),
        // The in-IDE coding assistant (specs/ide/coding-assistant.md)
        .target(name: "YcodeAssistant", dependencies: ["YcodeSubprocess", "YcodeBuild", "SwiftCodeExtensions", .product(name: "Crypto", package: "swift-crypto")],
                exclude: ["Tools/validate_tools.py", "Resources/System Assets", "Reverse/ReverseBridge.mjs"],
                resources: [.copy("System Assets"), .copy("Resources/SDKHosts"), .copy("Resources/ReverseBridge.mjs")]),
        .testTarget(name: "YcodeAssistantTests", dependencies: ["YcodeAssistant", "YcodeSubprocess"]),
        // Legacy targets
        .target(name: "SwiftCodeGitHub"),
        .testTarget(name: "SwiftCodeGitHubTests", dependencies: ["SwiftCodeGitHub"]),
        .target(name: "SwiftCodeExtensions", dependencies: ["YcodeSubprocess", "YcodeLanguage", "YcodeDebug"],
                resources: [.copy("Resources/extension-host.js")]),
        .testTarget(name: "SwiftCodeExtensionsTests", dependencies: ["SwiftCodeExtensions"]),
        .target(name: "SwiftCodeCloud", dependencies: ["YcodeAssistant"]),
        .testTarget(name: "SwiftCodeCloudTests", dependencies: ["SwiftCodeCloud", "YcodeAssistant"]),
        .target(name: "SwiftCodePaywall"),
        .testTarget(name: "SwiftCodePaywallTests", dependencies: ["SwiftCodePaywall"]),
        .target(name: "SwiftCodeConnect", dependencies: ["YcodeAssistant"]),
        .testTarget(name: "SwiftCodeConnectTests", dependencies: ["SwiftCodeConnect"]),
        .target(name: "SwiftCodeCollaboration"),
        .testTarget(name: "SwiftCodeCollaborationTests", dependencies: ["SwiftCodeCollaboration"]),
        .testTarget(name: "SwiftCodeGoogleAuthTests", dependencies: ["YcodeAssistant", "SwiftCodeCloud"]),
        .target(name: "SwiftCodeSDK", dependencies: ["SwiftCodeExtensions", "YcodeSubprocess", "YcodeAssistant", "YcodeBuild", "YcodeIDECore",
                                                 .product(name: "Crypto", package: "swift-crypto")],
                resources: [.copy("Resources/SwiftCodeSDK.json")]),
        .target(name: "SwiftCodeSDKStudio", dependencies: ["SwiftCodeSDK", "SwiftCodeExtensions"]),
        .testTarget(name: "SwiftCodeSDKTests", dependencies: ["SwiftCodeSDK", "SwiftCodeExtensions", "SwiftCodeSDKStudio", "YcodeAssistant"]),
        .executableTarget(name: "SwiftCodeSDKCLI", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKProjectGenerator", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKProjectInspector", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKExtensionValidator", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKDiagnostics", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKDocumentationIndexer", dependencies: ["SwiftCodeSDK"]),
        // Inline code completion
        .target(name: "YcodeCompletion", dependencies: ["YcodeAssistant"]),
        .testTarget(name: "YcodeCompletionTests", dependencies: ["YcodeCompletion", "YcodeAssistant"]),
        // Build & debug
        .target(name: "YcodeBuild", dependencies: ["YcodeProject", "YcodePlist", "YcodeWorkspace", "YcodeSubprocess"]),
        .target(name: "YcodeDebug", dependencies: ["YcodeSubprocess"]),
        .testTarget(name: "YcodeBuildTests", dependencies: ["YcodeBuild"]),
        .target(name: "YcodePreviews", dependencies: ["YcodeBuild", "YcodeSubprocess"]),
        .testTarget(name: "YcodePreviewsTests", dependencies: ["YcodePreviews"]),
        .testTarget(name: "YcodeDebugTests", dependencies: ["YcodeDebug"]),
        .target(name: "YcodeLanguage", dependencies: ["YcodeDebug", "YcodeSubprocess"]),
        .testTarget(name: "YcodeLanguageTests", dependencies: ["YcodeLanguage", "YcodeDebug"]),
        .testTarget(name: "YcodePlistTests", dependencies: ["YcodePlist"]),
        .testTarget(name: "YcodeProjectTests", dependencies: ["YcodeProject"], resources: [.copy("Fixtures")]),
        .testTarget(name: "YcodeWorkspaceTests", dependencies: ["YcodeWorkspace"], resources: [.copy("Fixtures")]),
        .testTarget(name: "YcodeSettingsTests", dependencies: ["YcodeSettings"]),
        .testTarget(name: "YcodeMachOTests", dependencies: ["YcodeMachO"]),
        .testTarget(name: "YcodeDarwinABITests", dependencies: ["YcodeDarwinABI"]),
        .testTarget(name: "YcodeDarwinKernelTests", dependencies: ["YcodeDarwinKernel"]),
        .testTarget(name: "YcodeXPCTests", dependencies: ["YcodeXPC"]),
        .testTarget(name: "YcodeMetalHostTests", dependencies: ["YcodeMetalHost", "YcodeXPC", "YcodeDarwinKernel"]),
        .testTarget(name: "YcodeVulkanTests", dependencies: ["YcodeVulkan"]),
        .testTarget(name: "YcodeHostServicesTests", dependencies: ["YcodeHostServices", "YcodeDarwinKernel", "YcodeXPC", "CYcodeCamera", "CYcodeCodec", "YcodeDisplayStream"]),
        .testTarget(name: "YcodeSimdTests", dependencies: ["ycode-simd"]),
        .testTarget(name: "YcodeDisplayStreamTests", dependencies: ["YcodeDisplayStream", "CYcodeCodec"]),
        .target(name: "YcodeRemoteViewer", dependencies: ["YcodeDisplayStream", "CYcodeCodec", "CYcodeVideo", "YcodeDeviceModel"]),
        .testTarget(name: "YcodeRemoteViewerTests", dependencies: ["YcodeRemoteViewer", "YcodeDisplayStream", "YcodeDeviceModel", "CYcodeCodec"]),
        .target(name: "YcodeRelease"),
        .testTarget(name: "YcodeReleaseTests", dependencies: ["YcodeRelease"]),
        .target(name: "YcodeTestAgent", dependencies: ["YcodeRelease"]),
        .target(name: "CYcodeTestAgentLoader", dependencies: ["YcodeTestAgent"]),
        .target(name: "YcodeDeviceUI", dependencies: ["YcodeDeviceModel"]),
        .testTarget(name: "YcodeDeviceUITests", dependencies: ["YcodeDeviceUI", "YcodeDeviceModel"]),
    ]
)

#if !os(macOS)
package.targets += [
    .target(name: "YcodeRemoteViewerSDL", dependencies: ["YcodeRemoteViewer", "YcodeDisplayStream", "YcodeDeviceModel", "YcodeSimLink"],
            cSettings: [.headerSearchPath("include")],
            linkerSettings: [.linkedLibrary("SDL2", .when(platforms: [.linux]))]),
    .executableTarget(name: "ycode-sim-viewer", dependencies: ["YcodeRelease", "YcodeRemoteViewerSDL", "YcodeRemoteViewer", "YcodeDisplayStream"]),
]
#endif

#if os(macOS)
package.products += [.library(name: "YcodeUI", targets: ["YcodeUI"]),
                     .executable(name: "YcodeApp", targets: ["YcodeApp"])]
package.targets += [
    .target(name: "YcodeUI", dependencies: ["YcodeMCP", "YcodeIDECore", "YcodeCompletion", "YcodePreviews", "YcodeProject", "YcodeWorkspace", "YcodeSettings", "YcodeBuild", "YcodeDebug", "YcodeLanguage", "YcodeXcodebuild", "YcodeSubprocess", "YcodeAssistant", "SwiftCodeGitHub", "SwiftCodeExtensions", "YcodeSimFeatures", "YcodeDeviceModel", "YcodeDeviceUI", "YcodeProfiler", "SwiftCodeCloud", "SwiftCodePaywall", "SwiftCodeSDK", "YcodeHealthStore", "YcodeIDEShell",
                                            "SwiftCodeConnect", "SwiftCodeCollaboration"]),
    .executableTarget(name: "YcodeApp", dependencies: ["YcodeRelease", "YcodeUI"]),
    .testTarget(name: "YcodeUITests", dependencies: ["YcodeMCP", "YcodeUI", "YcodeIDECore", "YcodeCompletion", "YcodePreviews", "YcodeDisplayStream", "YcodeSimFeatures", "YcodeDeviceModel", "YcodeDeviceUI", "YcodeBuild", "YcodeDebug", "YcodeLanguage", "YcodeXcodebuild", "YcodeSubprocess", "YcodeAssistant", "SwiftCodeExtensions", "YcodeProfiler", "YcodeBuildServer", "YcodeIDEShell", "SwiftCodeCloud", "SwiftCodeSDK", "YcodeIcon"]),
]
#endif

package.targets += [
    .target(name: "YcodeSimLink", dependencies: ["YcodeDisplayStream", .product(name: "Crypto", package: "swift-crypto")]),
    .testTarget(name: "YcodeSimLinkTests", dependencies: ["YcodeSimLink", "YcodeDisplayStream"]),
    .executableTarget(name: "ycode-simhost", dependencies: ["YcodeRelease", "YcodeSimLink"]),
    .target(name: "CYcodeOpenXR", cSettings: [.headerSearchPath("include")]),
    .target(name: "YcodeXRViewer", dependencies: ["CYcodeOpenXR", "CYcodeVideo", "CYcodeCodec", "YcodeDisplayStream", "YcodeRemoteViewer", "YcodeXRReprojection"]),
    .executableTarget(name: "ycode-xr-viewer", dependencies: ["YcodeRelease", "YcodeXRViewer", "YcodeSimLink", "YcodeDisplayStream"]),
    .testTarget(name: "YcodeXRViewerTests", dependencies: ["YcodeXRViewer", "YcodeDisplayStream", "YcodeRemoteViewer", "CYcodeCodec", "CYcodeOpenXR", "CYcodeVideo"]),
    .target(name: "CYcodeXRReprojection", cSettings: [.headerSearchPath("include")]),
    .target(name: "YcodeXRReprojection", dependencies: ["CYcodeXRReprojection", "CYcodeCodec", "YcodeDisplayStream"]),
    .testTarget(name: "YcodeXRReprojectionTests", dependencies: ["YcodeXRReprojection", "YcodeDisplayStream", "CYcodeVideo"]),
]

package.dependencies += [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")]
package.dependencies += [.package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")]
package.dependencies += [.package(path: "../frameworks/storekit")]

package.targets += [
    .target(name: "YcodeSyntax", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                                                .product(name: "SwiftParser", package: "swift-syntax")]),
    .testTarget(name: "YcodeSyntaxTests", dependencies: ["YcodeSyntax"]),
    .executableTarget(name: "ycode-syntax-bench", dependencies: ["YcodeSyntax"]),
]

package.targets += [
    .target(name: "YcodeIDECore", dependencies: ["YcodeRelease", "YcodeSyntax", "YcodeProject", "YcodeWorkspace", "YcodeSettings", "YcodePlist", "YcodeBuild", "YcodeDebug",
                                                 "YcodeLanguage", "YcodeXcodebuild", "YcodeSubprocess", "YcodeAssistant", "YcodeCompletion", "YcodeProfiler",
                                                 "YcodePreviews", "YcodeDeviceModel", "YcodeSimFeatures", "YcodeStrings", "YcodeSigning",
                                                 .product(name: "StoreKitConfiguration", package: "storekit"),
                                                 .product(name: "StoreKitEngine", package: "storekit"),
                                                 "YcodeHealthStore",
                                                 .product(name: "Crypto", package: "swift-crypto")], resources: [.copy("Resources/Licenses"), .copy("Resources/File Templates")]),
    .testTarget(name: "YcodeIDECoreTests", dependencies: ["YcodeIDECore", "YcodeSyntax", "YcodeProject", "YcodeWorkspace", "YcodeSettings", "YcodePlist",
                                                          "YcodeBuild", "YcodeDebug", "YcodeLanguage", "YcodeXcodebuild", "YcodeSubprocess",
                                                          "YcodeAssistant", "YcodeProfiler", "YcodePreviews", "YcodeDeviceModel", "YcodeSimFeatures",
                                                          "YcodeSigning",
                                                          .product(name: "StoreKitConfiguration", package: "storekit"),
                                                          .product(name: "StoreKitEngine", package: "storekit"),
                                                          "YcodeHealthStore"],
                exclude: ["Fixtures"]),
]

package.products += [.library(name: "YcodeIcon", targets: ["YcodeIcon"]),
                     .library(name: "YcodeAssetCatalog", targets: ["YcodeAssetCatalog"])]
package.targets += [
    .target(name: "YcodeIcon"),
    .target(name: "YcodeAssetCatalog", dependencies: ["YcodeIcon"]),
    .testTarget(name: "YcodeIconTests", dependencies: ["YcodeIcon"]),
    .testTarget(name: "YcodeAssetCatalogTests", dependencies: ["YcodeAssetCatalog", "YcodeIcon"]),
]

package.products += [.library(name: "YcodeStrings", targets: ["YcodeStrings"])]
package.targets += [
    .target(name: "YcodeStrings", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                                                 .product(name: "SwiftParser", package: "swift-syntax")]),
    .testTarget(name: "YcodeStringsTests", dependencies: ["YcodeStrings"]),
]

package.products += [.executable(name: "ycodebuild", targets: ["ycodebuild-cli"]),
                     .library(name: "YcodeBuildServer", targets: ["YcodeBuildServer"]),
                     .executable(name: "ycode-bsp", targets: ["ycode-bsp"])]
package.targets += [
    .target(name: "YcodeSigning"),
    .testTarget(name: "YcodeSigningTests", dependencies: ["YcodeSigning"]),
    .target(name: "YcodeXcodebuild", dependencies: ["YcodeRelease", "YcodeProject", "YcodeWorkspace", "YcodeSettings", "YcodePlist", "YcodeBuild", "YcodeSubprocess", "YcodeSigning"]),
    .executableTarget(name: "ycodebuild-cli", dependencies: ["YcodeRelease", "YcodeXcodebuild"], path: "Sources/ycodebuild-cli"),
    .testTarget(name: "YcodeXcodebuildTests", dependencies: ["YcodeXcodebuild", "YcodeProject"]),
    .target(name: "YcodeBuildServer", dependencies: ["YcodeXcodebuild", "YcodeBuild", "YcodeProject", "YcodeWorkspace", "YcodeSettings", "YcodeDebug", "YcodeSubprocess"]),
    .executableTarget(name: "ycode-bsp", dependencies: ["YcodeRelease", "YcodeBuildServer"]),
    .testTarget(name: "YcodeBuildServerTests", dependencies: ["YcodeBuildServer", "YcodeLanguage", "YcodeDebug", "YcodeXcodebuild", "ycode-bsp", "YcodeIDECore",
                                                              "YcodeSubprocess", "YcodeWorkspace"]),
]

package.products += [.library(name: "YcodeIDEShell", targets: ["YcodeIDEShell"]), .library(name: "YcodeEditorKit", targets: ["YcodeEditorKit"])]
package.targets += [
    .target(name: "YcodeEditorKit", dependencies: ["YcodeSyntax"]),
    .testTarget(name: "YcodeEditorKitTests", dependencies: ["YcodeEditorKit", "YcodeSyntax"]),
    .target(name: "YcodeIDEShell", dependencies: ["YcodeIDECore", "YcodeSyntax", "YcodeBuild", "YcodeXcodebuild", "YcodeSimLink", "YcodeEditorKit", "YcodeDebug", "YcodeAssistant",
                                                  "YcodePreviews", "YcodeDeviceModel"]),
    .testTarget(name: "YcodeIDEShellTests", dependencies: ["YcodeIDEShell", "YcodeIDECore", "YcodeSyntax", "YcodeBuild", "YcodeEditorKit", "YcodeCompletion", "YcodeDebug", "YcodeAssistant",
                                                          "YcodePreviews"]),
]

package.products += [.library(name: "YcodeMCP", targets: ["YcodeMCP"])]
package.targets += [
    .target(name: "YcodeMCP", dependencies: ["YcodeIDECore", "YcodeIDEShell", "YcodeAssistant", "YcodeCompletion", "YcodeBuild", "YcodePreviews",
                                             "YcodeProject", "YcodePlist", "YcodeSettings", "YcodeWorkspace", "YcodeSubprocess", "YcodeMachO", "SwiftCodeGitHub",
                                             "SwiftCodeExtensions",
                                             .product(name: "SwiftSyntax", package: "swift-syntax"),
                                             .product(name: "SwiftParser", package: "swift-syntax"),
                                             .product(name: "Crypto", package: "swift-crypto")],
            resources: [.copy("Resources/ReverseBridge.mjs")]),
    .testTarget(name: "YcodeMCPTests", dependencies: ["YcodeMCP", "YcodeIDECore", "YcodeAssistant", "YcodeCompletion", "YcodeBuild", "ycode"], resources: [.copy("Resources/ReverseBridge.mjs")]),
]
if let i = package.targets.firstIndex(where: { $0.name == "ycode" }) {
    package.targets[i].dependencies += ["YcodeMCP", "YcodeIDEShell"]
}

#if os(Linux)
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/../frameworks/swiftui/Package.swift") {
    package.dependencies += [.package(path: "../frameworks/swiftui")]
    package.products += [.executable(name: "ycode-ide", targets: ["ycode-ide"])]
    package.targets += [
        .executableTarget(name: "ycode-ide", dependencies: ["YcodeRelease", "YcodeIDEShell", "YcodeIDECore", "YcodeSyntax", "YcodeBuild", "YcodeEditorKit", "YcodeCompletion", "YcodeAssistant",
                                                          "YcodePreviews", "SwiftCodeExtensions", "SwiftCodeSDK", "SwiftCodeSDKStudio", "SwiftCodePaywall",
                                                          "SwiftCodeCloud", "SwiftCodeGitHub",
                                                          .product(name: "StoreKitConfiguration", package: "storekit"),
                                                          .product(name: "SwiftUI", package: "swiftui"),
                                                          .product(name: "OVPlatform", package: "swiftui"),
                                                          .product(name: "OVDBus", package: "swiftui"),
                                                          .product(name: "OVText", package: "swiftui"),
                                                          "YcodeUI",
                                                          "YcodeDarwinKernel"]),
    ]
}
#else
package.products += [.executable(name: "ycode-ide", targets: ["ycode-ide"])]
package.targets += [
    .executableTarget(name: "ycode-ide", dependencies: ["YcodeRelease", "YcodeIDEShell", "YcodeIDECore", "YcodeSyntax", "YcodeBuild", "YcodeEditorKit", "YcodeCompletion", "YcodeAssistant",
                                                      "YcodePreviews", "SwiftCodeExtensions", "SwiftCodeSDK", "SwiftCodeSDKStudio", "SwiftCodePaywall",
                                                      "SwiftCodeCloud", "SwiftCodeGitHub",
                                                      .product(name: "StoreKitConfiguration", package: "storekit"),
                                                      "YcodeUI",
                                                      "YcodeDarwinKernel"]),
]
#endif
