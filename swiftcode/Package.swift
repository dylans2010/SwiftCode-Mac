// swift-tools-version: 6.0
import Foundation
import PackageDescription

let package = Package(
    name: "SwiftCode",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SwiftCodePlist", targets: ["SwiftCodePlist"]),
        .library(name: "SwiftCodeProject", targets: ["SwiftCodeProject"]),
        .library(name: "SwiftCodeWorkspace", targets: ["SwiftCodeWorkspace"]),
        .library(name: "SwiftCodeSettings", targets: ["SwiftCodeSettings"]),
        .library(name: "SwiftCodeMachO", targets: ["SwiftCodeMachO"]),
        .library(name: "SwiftCodeDarwinABI", targets: ["SwiftCodeDarwinABI"]),
        .library(name: "SwiftCodeDarwinKernel", targets: ["SwiftCodeDarwinKernel"]),
        .library(name: "SwiftCodeXPC", targets: ["SwiftCodeXPC"]),
        .library(name: "SwiftCodeSimFeatures", targets: ["SwiftCodeSimFeatures"]),
        .executable(name: "swiftcode-simd", targets: ["swiftcode-simd"]),
        .executable(name: "swiftcode", targets: ["swiftcode"]),
        .library(name: "SwiftCodeBuild", targets: ["SwiftCodeBuild"]),
        .library(name: "SwiftCodeDebug", targets: ["SwiftCodeDebug"]),
        .library(name: "SwiftCodeLanguage", targets: ["SwiftCodeLanguage"]),
        .library(name: "SwiftCodeSubprocess", targets: ["SwiftCodeSubprocess"]),
        .library(name: "SwiftCodeAssistant", targets: ["SwiftCodeAssistant"]),
        .library(name: "SwiftCodeCompletion", targets: ["SwiftCodeCompletion"]),
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
        .library(name: "SwiftCodeProfiler", targets: ["SwiftCodeProfiler"]),
        .library(name: "SwiftCodeGaugeAgent", type: .dynamic, targets: ["CSwiftCodeGaugeAgent"]),
        .library(name: "SwiftCodePreviews", targets: ["SwiftCodePreviews"]),
    ],
    targets: [
        .target(name: "SwiftCodePlist"),
        .target(name: "SwiftCodeProject", dependencies: ["SwiftCodePlist"]),
        .target(name: "SwiftCodeWorkspace", dependencies: ["SwiftCodeProject"]),
        .target(name: "SwiftCodeSettings", dependencies: ["SwiftCodeProject"]),
        .target(name: "SwiftCodeMachO"),
        .target(name: "CSwiftCodeGauge"),
        .target(name: "CSwiftCodeGaugeAgent"),
        .target(name: "SwiftCodeProfiler", dependencies: ["SwiftCodeMachO", "CSwiftCodeGauge"]),
        .testTarget(name: "SwiftCodeProfilerTests", dependencies: ["SwiftCodeProfiler", "SwiftCodeMachO"]),
        .target(name: "SwiftCodeDarwinABI"),
        .target(name: "SwiftCodeDarwinKernel", dependencies: ["SwiftCodeDarwinABI"]),
        .target(name: "SwiftCodeXPC"),
        .target(name: "SwiftCodeHostServices", dependencies: ["SwiftCodeDarwinABI", "SwiftCodeDarwinKernel", "SwiftCodeXPC", "CSwiftCodeCamera", "SwiftCodeDisplayStream"]),
        .target(name: "CSwiftCodeCamera", linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
        .target(name: "SwiftCodeMetalHost", dependencies: ["SwiftCodeXPC", "SwiftCodeDarwinKernel"]),
        .target(name: "CVulkan"),
        .target(name: "SwiftCodeVulkan", dependencies: ["CVulkan", "SwiftCodeMetalHost"], exclude: ["shaders"]),
        .target(name: "CKVM"),
        .target(name: "SwiftCodeHypervisor", dependencies: ["CKVM", "SwiftCodeDarwinABI"]),
        .target(name: "CSwiftCodeCodec", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "CSwiftCodeVideo", exclude: ["nvheaders/ffnvcodec/README.md"], cSettings: [.headerSearchPath("nvheaders")], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "SwiftCodeDisplayStream"),
        .target(name: "SwiftCodeSimFeatures"),
        .testTarget(name: "SwiftCodeSimFeaturesTests", dependencies: ["SwiftCodeSimFeatures"]),
        .systemLibrary(name: "CSQLite"),
        .target(name: "SwiftCodeHealthStore", dependencies: ["CSQLite", "SwiftCodeSimFeatures"]),
        .testTarget(name: "SwiftCodeHealthStoreTests", dependencies: ["SwiftCodeHealthStore", "SwiftCodeSimFeatures"]),
        .target(name: "SwiftCodeDeviceModel"),
        .testTarget(name: "SwiftCodeDeviceModelTests", dependencies: ["SwiftCodeDeviceModel"]),
        .executableTarget(name: "swiftcode-simd", dependencies: ["SwiftCodeRelease", "SwiftCodeHypervisor", "SwiftCodeDarwinABI", "SwiftCodeDarwinKernel", "SwiftCodeMachO", "SwiftCodeXPC", "SwiftCodeHostServices", "SwiftCodeMetalHost", "SwiftCodeVulkan", "SwiftCodeDisplayStream", "CSwiftCodeCodec", "CSwiftCodeVideo", "SwiftCodeSimFeatures", "SwiftCodeHealthStore", "SwiftCodeProfiler", "SwiftCodeDebug", "SwiftCodeXRReprojection"]),
        .executableTarget(name: "swiftcode", dependencies: ["SwiftCodeRelease", "SwiftCodePlist", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodeMachO", "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodePreviews", "SwiftCodeProfiler", "SwiftCodeBuildServer", "SwiftCodeXcodebuild", "SwiftCodeAssetCatalog", "SwiftCodeIDECore", "SwiftCodeStrings", "SwiftCodeSimLink", "SwiftCodeCompletion"]),
        .target(name: "SwiftCodeSubprocess"),
        .testTarget(name: "SwiftCodeSubprocessTests", dependencies: ["SwiftCodeSubprocess"]),
        .target(name: "SwiftCodeAssistant", dependencies: ["SwiftCodeSubprocess", "SwiftCodeBuild", .product(name: "Crypto", package: "swift-crypto")], resources: [.copy("Resources/System Assets"), .copy("Resources/SDKHosts"), .copy("Resources/ReverseBridge.mjs")]),
        .testTarget(name: "SwiftCodeAssistantTests", dependencies: ["SwiftCodeAssistant", "SwiftCodeSubprocess"]),
        .target(name: "SwiftCodeGitHub"),
        .testTarget(name: "SwiftCodeGitHubTests", dependencies: ["SwiftCodeGitHub"]),
        .target(name: "SwiftCodeExtensions", dependencies: ["SwiftCodeSubprocess", "SwiftCodeLanguage", "SwiftCodeDebug"],
                resources: [.copy("Resources/extension-host.js")]),
        .testTarget(name: "SwiftCodeExtensionsTests", dependencies: ["SwiftCodeExtensions"]),
        .target(name: "SwiftCodeCloud", dependencies: ["SwiftCodeAssistant"]),
        .testTarget(name: "SwiftCodeCloudTests", dependencies: ["SwiftCodeCloud", "SwiftCodeAssistant"]),
        .target(name: "SwiftCodePaywall"),
        .testTarget(name: "SwiftCodePaywallTests", dependencies: ["SwiftCodePaywall"]),
        .target(name: "SwiftCodeSDK", dependencies: ["SwiftCodeExtensions", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeBuild", "SwiftCodeIDECore",
                                                 .product(name: "Crypto", package: "swift-crypto")],
                resources: [.copy("Resources/SwiftCodeSDK.json")]),
        .target(name: "SwiftCodeSDKStudio", dependencies: ["SwiftCodeSDK", "SwiftCodeExtensions"]),
        .testTarget(name: "SwiftCodeSDKTests", dependencies: ["SwiftCodeSDK", "SwiftCodeExtensions", "SwiftCodeSDKStudio", "SwiftCodeAssistant"]),
        .executableTarget(name: "SwiftCodeSDKCLI", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKProjectGenerator", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKProjectInspector", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKExtensionValidator", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKDiagnostics", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKDocumentationIndexer", dependencies: ["SwiftCodeSDK"]),
        .target(name: "SwiftCodeCompletion", dependencies: ["SwiftCodeAssistant"]),
        .testTarget(name: "SwiftCodeCompletionTests", dependencies: ["SwiftCodeCompletion", "SwiftCodeAssistant"]),
        .target(name: "SwiftCodeBuild", dependencies: ["SwiftCodeProject", "SwiftCodePlist", "SwiftCodeWorkspace", "SwiftCodeSubprocess"]),
        .target(name: "SwiftCodeDebug", dependencies: ["SwiftCodeSubprocess"]),
        .testTarget(name: "SwiftCodeBuildTests", dependencies: ["SwiftCodeBuild"]),
        .target(name: "SwiftCodePreviews", dependencies: ["SwiftCodeBuild", "SwiftCodeSubprocess"]),
        .testTarget(name: "SwiftCodePreviewsTests", dependencies: ["SwiftCodePreviews"]),
        .testTarget(name: "SwiftCodeDebugTests", dependencies: ["SwiftCodeDebug"]),
        .target(name: "SwiftCodeLanguage", dependencies: ["SwiftCodeDebug", "SwiftCodeSubprocess"]),
        .testTarget(name: "SwiftCodeLanguageTests", dependencies: ["SwiftCodeLanguage", "SwiftCodeDebug"]),
        .testTarget(name: "SwiftCodePlistTests", dependencies: ["SwiftCodePlist"]),
        .testTarget(name: "SwiftCodeProjectTests", dependencies: ["SwiftCodeProject"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SwiftCodeWorkspaceTests", dependencies: ["SwiftCodeWorkspace"], resources: [.copy("Fixtures")]),
        .testTarget(name: "SwiftCodeSettingsTests", dependencies: ["SwiftCodeSettings"]),
        .testTarget(name: "SwiftCodeMachOTests", dependencies: ["SwiftCodeMachO"]),
        .testTarget(name: "SwiftCodeDarwinABITests", dependencies: ["SwiftCodeDarwinABI"]),
        .testTarget(name: "SwiftCodeDarwinKernelTests", dependencies: ["SwiftCodeDarwinKernel"]),
        .testTarget(name: "SwiftCodeXPCTests", dependencies: ["SwiftCodeXPC"]),
        .testTarget(name: "SwiftCodeMetalHostTests", dependencies: ["SwiftCodeMetalHost", "SwiftCodeXPC", "SwiftCodeDarwinKernel"]),
        .testTarget(name: "SwiftCodeVulkanTests", dependencies: ["SwiftCodeVulkan"]),
        .testTarget(name: "SwiftCodeHostServicesTests", dependencies: ["SwiftCodeHostServices", "SwiftCodeDarwinKernel", "SwiftCodeXPC", "CSwiftCodeCamera", "CSwiftCodeCodec", "SwiftCodeDisplayStream"]),
        .testTarget(name: "SwiftCodeSimdTests", dependencies: ["swiftcode-simd"]),
        .testTarget(name: "SwiftCodeDisplayStreamTests", dependencies: ["SwiftCodeDisplayStream", "CSwiftCodeCodec"]),
        .target(name: "SwiftCodeRemoteViewer", dependencies: ["SwiftCodeDisplayStream", "CSwiftCodeCodec", "CSwiftCodeVideo", "SwiftCodeDeviceModel"]),
        .testTarget(name: "SwiftCodeRemoteViewerTests", dependencies: ["SwiftCodeRemoteViewer", "SwiftCodeDisplayStream", "SwiftCodeDeviceModel", "CSwiftCodeCodec"]),
    ]
)

package.targets += [
    .target(name: "SwiftCodeRelease"),
    .testTarget(name: "SwiftCodeReleaseTests", dependencies: ["SwiftCodeRelease"]),
]

#if os(macOS)
package.products += [.executable(name: "SwiftCodeApp", targets: ["SwiftCodeApp"]),
                     .executable(name: "swiftcode-sim-viewer", targets: ["swiftcode-sim-viewer"]),
                     .library(name: "SwiftCodeTestAgent", type: .dynamic, targets: ["SwiftCodeTestAgent", "CSwiftCodeTestAgentLoader"]),
                     .library(name: "SwiftCodeConnect", targets: ["SwiftCodeConnect"]),
                     .library(name: "SwiftCodeCollaboration", targets: ["SwiftCodeCollaboration"])]
package.targets += [
    .target(name: "CSwiftCodeTestAgentLoader"),
    .target(name: "SwiftCodeTestAgent"),
    .target(name: "SwiftCodeConnect", dependencies: ["SwiftCodeAssistant"]),
    .testTarget(name: "SwiftCodeConnectTests", dependencies: ["SwiftCodeConnect"]),
    .target(name: "SwiftCodeCollaboration"),
    .testTarget(name: "SwiftCodeCollaborationTests", dependencies: ["SwiftCodeCollaboration"]),
    .target(name: "SwiftCodeDeviceUI", dependencies: ["SwiftCodeDisplayStream", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel"]),
    .testTarget(name: "SwiftCodeDeviceUITests", dependencies: ["SwiftCodeDeviceUI", "SwiftCodeDeviceModel", "SwiftCodeDisplayStream"]),
    .executableTarget(name: "swiftcode-sim-viewer", dependencies: ["SwiftCodeRelease", "SwiftCodeDisplayStream", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel", "SwiftCodeDeviceUI", "SwiftCodeRemoteViewer", "SwiftCodeSimLink"]),
    .target(name: "SwiftCodeUI", dependencies: ["SwiftCodeMCP", "SwiftCodeIDECore", "SwiftCodeCompletion", "SwiftCodePreviews", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeGitHub", "SwiftCodeExtensions", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel", "SwiftCodeDeviceUI", "SwiftCodeProfiler", "SwiftCodeCloud", "SwiftCodePaywall", "SwiftCodeSDK", "SwiftCodeHealthStore", "SwiftCodeIDEShell",
                                             "SwiftCodeConnect", "SwiftCodeCollaboration",
                                             "SwiftCodeHypervisor", "SwiftCodeIcon",
                                             .product(name: "StoreKitConfiguration", package: "storekit"), .product(name: "Markdown", package: "swift-markdown")], resources: [.copy("Resources/Sounds")]),
    .executableTarget(name: "SwiftCodeApp", dependencies: ["SwiftCodeRelease", "SwiftCodeUI"]),
    .testTarget(name: "SwiftCodeUITests", dependencies: ["SwiftCodeMCP", "SwiftCodeUI", "SwiftCodeIDECore", "SwiftCodeCompletion", "SwiftCodePreviews", "SwiftCodeDisplayStream", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel", "SwiftCodeDeviceUI", "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeExtensions", "SwiftCodeProfiler", "SwiftCodeBuildServer", "SwiftCodeIDEShell", "SwiftCodeCloud", "SwiftCodeSDK", "SwiftCodeIcon"]),
]
#else
package.products += [.executable(name: "swiftcode-sim-viewer", targets: ["swiftcode-sim-viewer"]),
                     .library(name: "SwiftCodeRemoteViewerSDL", targets: ["SwiftCodeRemoteViewerSDL"])]
package.targets += [
    .target(name: "SwiftCodeRemoteViewerSDL", dependencies: ["SwiftCodeRemoteViewer", "SwiftCodeDisplayStream", "SwiftCodeDeviceModel", "SwiftCodeSimLink"],
            linkerSettings: [.linkedLibrary("dl")]),
    .executableTarget(name: "swiftcode-sim-viewer", dependencies: ["SwiftCodeRelease", "SwiftCodeRemoteViewerSDL", "SwiftCodeRemoteViewer", "SwiftCodeDisplayStream"]),
]
#endif

package.dependencies += [.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")]
package.products += [.library(name: "SwiftCodeSimLink", targets: ["SwiftCodeSimLink"]),
                     .executable(name: "swiftcode-simhost", targets: ["swiftcode-simhost"])]
package.targets += [
    .target(name: "SwiftCodeSimLink", dependencies: ["SwiftCodeDisplayStream", .product(name: "Crypto", package: "swift-crypto")]),
    .testTarget(name: "SwiftCodeSimLinkTests", dependencies: ["SwiftCodeSimLink", "SwiftCodeDisplayStream"]),
    .executableTarget(name: "swiftcode-simhost", dependencies: ["SwiftCodeRelease", "SwiftCodeSimLink"]),
]

package.products += [.executable(name: "swiftcode-xr-viewer", targets: ["swiftcode-xr-viewer"])]
package.targets += [
    .target(name: "CSwiftCodeOpenXR", exclude: ["openxr/LICENSE"], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
    .target(name: "SwiftCodeXRViewer", dependencies: ["CSwiftCodeOpenXR", "CSwiftCodeVideo", "CSwiftCodeCodec", "SwiftCodeDisplayStream", "SwiftCodeRemoteViewer", "SwiftCodeXRReprojection"]),
    .executableTarget(name: "swiftcode-xr-viewer", dependencies: ["SwiftCodeRelease", "SwiftCodeXRViewer", "SwiftCodeSimLink", "SwiftCodeDisplayStream"]),
    .testTarget(name: "SwiftCodeXRViewerTests", dependencies: ["SwiftCodeXRViewer", "SwiftCodeDisplayStream", "SwiftCodeRemoteViewer", "CSwiftCodeCodec", "CSwiftCodeOpenXR", "CSwiftCodeVideo"]),
]

package.targets += [
    .target(name: "CSwiftCodeXRReprojection", exclude: ["shaders"], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux])), .linkedLibrary("pthread", .when(platforms: [.linux]))]),
    .target(name: "SwiftCodeXRReprojection", dependencies: ["CSwiftCodeXRReprojection", "CSwiftCodeCodec", "SwiftCodeDisplayStream"]),
    .testTarget(name: "SwiftCodeXRReprojectionTests", dependencies: ["SwiftCodeXRReprojection", "SwiftCodeDisplayStream", "CSwiftCodeVideo"]),
]

package.dependencies += [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")]

package.dependencies += [.package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")]

package.dependencies += [.package(path: "../frameworks/storekit")]
package.products += [.library(name: "SwiftCodeSyntax", targets: ["SwiftCodeSyntax"])]
package.targets += [
    .target(name: "SwiftCodeSyntax", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                                                .product(name: "SwiftParser", package: "swift-syntax"),
                                                .product(name: "SwiftIDEUtils", package: "swift-syntax")]),
    .testTarget(name: "SwiftCodeSyntaxTests", dependencies: ["SwiftCodeSyntax"]),
    .executableTarget(name: "swiftcode-syntax-bench", dependencies: ["SwiftCodeSyntax"]),
]

package.targets += [
    .target(name: "SwiftCodeIDECore", dependencies: ["SwiftCodeRelease", "SwiftCodeSyntax", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodePlist", "SwiftCodeBuild", "SwiftCodeDebug",
                                                 "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeCompletion", "SwiftCodeProfiler",
                                                 "SwiftCodePreviews", "SwiftCodeDeviceModel", "SwiftCodeSimFeatures", "SwiftCodeStrings", "SwiftCodeSigning",
                                                 .product(name: "StoreKitConfiguration", package: "storekit"),
                                                 .product(name: "StoreKitEngine", package: "storekit"),
                                                 "SwiftCodeHealthStore",
                                                 .product(name: "Crypto", package: "swift-crypto")], resources: [.copy("Resources/Licenses"), .copy("Resources/File Templates")]),
    .testTarget(name: "SwiftCodeIDECoreTests", dependencies: ["SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodePlist",
                                                          "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess",
                                                          "SwiftCodeAssistant", "SwiftCodeProfiler", "SwiftCodePreviews", "SwiftCodeDeviceModel", "SwiftCodeSimFeatures",
                                                          "SwiftCodeSigning",
                                                          .product(name: "StoreKitConfiguration", package: "storekit"),
                                                          .product(name: "StoreKitEngine", package: "storekit"),
                                                          "SwiftCodeHealthStore"],
                exclude: ["Fixtures"]),
]

package.products += [.library(name: "SwiftCodeIcon", targets: ["SwiftCodeIcon"]),
                     .library(name: "SwiftCodeAssetCatalog", targets: ["SwiftCodeAssetCatalog"])]
package.targets += [
    .target(name: "SwiftCodeIcon"),
    .target(name: "SwiftCodeAssetCatalog", dependencies: ["SwiftCodeIcon"]),
    .testTarget(name: "SwiftCodeIconTests", dependencies: ["SwiftCodeIcon"]),
    .testTarget(name: "SwiftCodeAssetCatalogTests", dependencies: ["SwiftCodeAssetCatalog", "SwiftCodeIcon"]),
]

package.products += [.library(name: "SwiftCodeStrings", targets: ["SwiftCodeStrings"])]
package.targets += [
    .target(name: "SwiftCodeStrings", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                                                 .product(name: "SwiftParser", package: "swift-syntax")]),
    .testTarget(name: "SwiftCodeStringsTests", dependencies: ["SwiftCodeStrings"]),
]

package.products += [.executable(name: "swiftcodebuild", targets: ["swiftcodebuild-cli"]),
                     .library(name: "SwiftCodeBuildServer", targets: ["SwiftCodeBuildServer"]),
                     .executable(name: "swiftcode-bsp", targets: ["swiftcode-bsp"])]
package.targets += [
    .target(name: "SwiftCodeSigning"),
    .testTarget(name: "SwiftCodeSigningTests", dependencies: ["SwiftCodeSigning"]),
    .target(name: "SwiftCodeXcodebuild", dependencies: ["SwiftCodeRelease", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodePlist", "SwiftCodeBuild", "SwiftCodeSubprocess", "SwiftCodeSigning"]),
    .executableTarget(name: "swiftcodebuild-cli", dependencies: ["SwiftCodeRelease", "SwiftCodeXcodebuild"], path: "Sources/swiftcodebuild-cli"),
    .testTarget(name: "SwiftCodeXcodebuildTests", dependencies: ["SwiftCodeXcodebuild", "SwiftCodeProject"]),
    .target(name: "SwiftCodeBuildServer", dependencies: ["SwiftCodeXcodebuild", "SwiftCodeBuild", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodeDebug", "SwiftCodeSubprocess"]),
    .executableTarget(name: "swiftcode-bsp", dependencies: ["SwiftCodeRelease", "SwiftCodeBuildServer"]),
    .testTarget(name: "SwiftCodeBuildServerTests", dependencies: ["SwiftCodeBuildServer", "SwiftCodeLanguage", "SwiftCodeDebug", "SwiftCodeXcodebuild", "swiftcode-bsp", "SwiftCodeIDECore",
                                                              "SwiftCodeSubprocess", "SwiftCodeWorkspace"]),
]

package.products += [.library(name: "SwiftCodeIDEShell", targets: ["SwiftCodeIDEShell"]), .library(name: "SwiftCodeEditorKit", targets: ["SwiftCodeEditorKit"])]
package.targets += [
    .target(name: "SwiftCodeEditorKit", dependencies: ["SwiftCodeSyntax"]),
    .testTarget(name: "SwiftCodeEditorKitTests", dependencies: ["SwiftCodeEditorKit", "SwiftCodeSyntax"]),
    .target(name: "SwiftCodeIDEShell", dependencies: ["SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeXcodebuild", "SwiftCodeSimLink", "SwiftCodeEditorKit", "SwiftCodeDebug", "SwiftCodeAssistant",
                                                  "SwiftCodePreviews", "SwiftCodeDeviceModel"]),
    .testTarget(name: "SwiftCodeIDEShellTests", dependencies: ["SwiftCodeIDEShell", "SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeEditorKit", "SwiftCodeCompletion", "SwiftCodeDebug", "SwiftCodeAssistant",
                                                          "SwiftCodePreviews"]),
]
package.products += [.library(name: "SwiftCodeMCP", targets: ["SwiftCodeMCP"])]
package.targets += [
    .target(name: "SwiftCodeMCP", dependencies: ["SwiftCodeIDECore", "SwiftCodeIDEShell", "SwiftCodeAssistant", "SwiftCodeCompletion", "SwiftCodeBuild", "SwiftCodePreviews",
                                             "SwiftCodeProject", "SwiftCodePlist", "SwiftCodeSettings", "SwiftCodeWorkspace", "SwiftCodeSubprocess", "SwiftCodeMachO", "SwiftCodeGitHub",
                                             "SwiftCodeExtensions",
                                             .product(name: "SwiftSyntax", package: "swift-syntax"),
                                             .product(name: "SwiftParser", package: "swift-syntax"),
                                             .product(name: "Crypto", package: "swift-crypto")],
            resources: [.copy("Resources/ReverseBridge.mjs")]),
    .testTarget(name: "SwiftCodeMCPTests", dependencies: ["SwiftCodeMCP", "SwiftCodeIDECore", "SwiftCodeAssistant", "SwiftCodeCompletion", "SwiftCodeBuild", "swiftcode"], resources: [.copy("Resources/ReverseBridge.mjs")]),
]
if let i = package.targets.firstIndex(where: { $0.name == "swiftcode" }) {
    package.targets[i].dependencies += ["SwiftCodeMCP", "SwiftCodeIDEShell"]
}

#if os(Linux)
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/../frameworks/swiftui/Package.swift") {
    package.dependencies += [.package(path: "../frameworks/swiftui")]
    package.products += [.executable(name: "swiftcode-ide", targets: ["swiftcode-ide"])]
    package.targets += [
        .executableTarget(name: "swiftcode-ide", dependencies: ["SwiftCodeRelease", "SwiftCodeIDEShell", "SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeEditorKit", "SwiftCodeCompletion", "SwiftCodeAssistant",
                                                          "SwiftCodePreviews", "SwiftCodeExtensions", "SwiftCodeSDK", "SwiftCodeSDKStudio", "SwiftCodePaywall",
                                                          "SwiftCodeCloud", "SwiftCodeGitHub",
                                                          .product(name: "StoreKitConfiguration", package: "storekit"),
                                                          .product(name: "SwiftUI", package: "swiftcode-swiftui"),
                                                          .product(name: "OVPlatform", package: "swiftcode-swiftui"),
                                                          .product(name: "OVDBus", package: "swiftcode-swiftui"),
                                                          .product(name: "OVText", package: "swiftcode-swiftui"),
                                                          "SwiftCodeUI",
                                                          "SwiftCodeDarwinKernel"]),
    ]
}
#else
package.products += [.executable(name: "swiftcode-ide", targets: ["swiftcode-ide"])]
package.targets += [
    .executableTarget(name: "swiftcode-ide", dependencies: ["SwiftCodeRelease", "SwiftCodeIDEShell", "SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeEditorKit", "SwiftCodeCompletion", "SwiftCodeAssistant",
                                                      "SwiftCodePreviews", "SwiftCodeExtensions", "SwiftCodeSDK", "SwiftCodeSDKStudio", "SwiftCodePaywall",
                                                      "SwiftCodeCloud", "SwiftCodeGitHub",
                                                      .product(name: "StoreKitConfiguration", package: "storekit"),
                                                      "SwiftCodeUI",
                                                      "SwiftCodeDarwinKernel"]),
]
#endif
