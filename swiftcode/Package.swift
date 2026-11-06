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
        // Extensions v2 platform (specs/ide/extensions-platform.md):
        // VS Code extension host, manifests, registry, grants.
        .library(name: "SwiftCodeExtensions", targets: ["SwiftCodeExtensions"]),
        // Cloud accounts and auth (specs/ide/cloud-accounts.md):
        // the Appwrite Account REST client, the Cloud framework
        // types, and the CloudManager orchestration.
        .library(name: "SwiftCodeCloud", targets: ["SwiftCodeCloud"]),
        // Google account auth (specs/ide/cloud-accounts.md §10):
        // Legacy's GoogleAccountAuthService — PKCE OAuth2 with a
        // loopback listener, ADC/Antigravity/gcloud fallbacks.
        // Separate target from SwiftCodeCloud: its Apple-only pieces
        // (AuthenticationServices, Network, Security, AppKit) stay
        // fenced here instead of landing in platform-clean SwiftCodeCloud.
        .library(name: "SwiftCodeGoogleAuth", targets: ["SwiftCodeGoogleAuth"]),
        // Paywall / entitlement runtime (specs/ide/storekit-paywall.md):
        // Apple StoreKit 2 products, Pro entitlement checks, the
        // paywall UI. No dependency on frameworks/storekit's
        // `StoreKit` product — that module re-implements the StoreKit
        // API under the same name and would shadow Apple's real one.
        .library(name: "SwiftCodePaywall", targets: ["SwiftCodePaywall"]),
        // SDK platform (specs/ide/sdk-platform.md): Legacy's SwiftCode/SDK —
        // versioned contracts, kits, host (API keys, capability broker,
        // registry, security, service adapters, runtime IPC) and the
        // Studio UI models. The `swiftcode` CLI and SDK tools are thin
        // executable wrappers over SwiftCodeSDK entry points.
        .library(name: "SwiftCodeSDK", targets: ["SwiftCodeSDK"]),
        .library(name: "SwiftCodeSDKStudio", targets: ["SwiftCodeSDKStudio"]),
        .executable(name: "swiftcode-sdk", targets: ["SwiftCodeSDKCLI"]),
        .executable(name: "project-generator", targets: ["SwiftCodeSDKProjectGenerator"]),
        .executable(name: "project-inspector", targets: ["SwiftCodeSDKProjectInspector"]),
        .executable(name: "extension-validator", targets: ["SwiftCodeSDKExtensionValidator"]),
        .executable(name: "diagnostics", targets: ["SwiftCodeSDKDiagnostics"]),
        .executable(name: "documentation-indexer", targets: ["SwiftCodeSDKDocumentationIndexer"]),
        // Gauge, the profiler (specs/ide/profiler.md): trace format, analysis, Linux recording
        .library(name: "SwiftCodeProfiler", targets: ["SwiftCodeProfiler"]),
        // Gauge's in-process sampler for Linux processes (LD_PRELOAD; profiler.md §3.2)
        .library(name: "SwiftCodeGaugeAgent", type: .dynamic, targets: ["CSwiftCodeGaugeAgent"]),
        .library(name: "SwiftCodePreviews", targets: ["SwiftCodePreviews"]),
    ],
    targets: [
        .target(name: "SwiftCodePlist"),
        .target(name: "SwiftCodeProject", dependencies: ["SwiftCodePlist"]),
        .target(name: "SwiftCodeWorkspace", dependencies: ["SwiftCodeProject"]),
        .target(name: "SwiftCodeSettings", dependencies: ["SwiftCodeProject"]),
        .target(name: "SwiftCodeMachO"),
        // Gauge (specs/ide/profiler.md)
        .target(name: "CSwiftCodeGauge"),
        .target(name: "CSwiftCodeGaugeAgent"),
        .target(name: "SwiftCodeProfiler", dependencies: ["SwiftCodeMachO", "CSwiftCodeGauge"]),
        .testTarget(name: "SwiftCodeProfilerTests", dependencies: ["SwiftCodeProfiler", "SwiftCodeMachO"]),
        // Simulator stage 2 (specs/simulator/vm-shim-protocol.md)
        .target(name: "SwiftCodeDarwinABI"),
        .target(name: "SwiftCodeDarwinKernel", dependencies: ["SwiftCodeDarwinABI"]),
        .target(name: "SwiftCodeXPC"),
        // Host services the VMM offers the guest (stage 7: IOSurface)
        .target(name: "SwiftCodeHostServices", dependencies: ["SwiftCodeDarwinABI", "SwiftCodeDarwinKernel", "SwiftCodeXPC", "CSwiftCodeCamera", "SwiftCodeDisplayStream"]),
        // The host camera layer's V4L2 access, JPEG decoder and pixel conversion (specs/simulator/camera-host.md)
        .target(name: "CSwiftCodeCamera", linkerSettings: [.linkedLibrary("m", .when(platforms: [.linux]))]),
        // Stage 8a (specs/simulator/stage8-contract.md §5): the Metal host service and its Vulkan back end
        .target(name: "SwiftCodeMetalHost", dependencies: ["SwiftCodeXPC", "SwiftCodeDarwinKernel"]),
        .target(name: "CVulkan"),
        .target(name: "SwiftCodeVulkan", dependencies: ["CVulkan", "SwiftCodeMetalHost"], exclude: ["shaders"]),
        .target(name: "CKVM"),
        .target(name: "SwiftCodeHypervisor", dependencies: ["CKVM", "SwiftCodeDarwinABI"]),
        // The live display stream and viewer input (specs/simulator/display-stream.md)
        .target(name: "CSwiftCodeCodec", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        // Low-latency H.264 through NVIDIA's NVENC / NVDEC, opened at run time (display-stream.md §14)
        .target(name: "CSwiftCodeVideo", exclude: ["nvheaders/ffnvcodec/README.md"], cSettings: [.headerSearchPath("nvheaders")], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "SwiftCodeDisplayStream"),
        // The simulator's settings features (specs/simulator/simulator-features.md, "SwiftCode implementation")
        .target(name: "SwiftCodeSimFeatures"),
        .testTarget(name: "SwiftCodeSimFeaturesTests", dependencies: ["SwiftCodeSimFeatures"]),
        // Shut-down edits of a device's HealthKit store: grants and seeded samples (specs/simulator/health-simulation.md, "SwiftCode implementation")
        .systemLibrary(name: "CSQLite"),
        .target(name: "SwiftCodeHealthStore", dependencies: ["CSQLite", "SwiftCodeSimFeatures"]),
        .testTarget(name: "SwiftCodeHealthStoreTests", dependencies: ["SwiftCodeHealthStore", "SwiftCodeSimFeatures"]),
        // The device windows' model: frames, zoom, the hub's sidebar, commands (specs/ide/device-hub.md, "SwiftCode implementation")
        .target(name: "SwiftCodeDeviceModel"),
        .testTarget(name: "SwiftCodeDeviceModelTests", dependencies: ["SwiftCodeDeviceModel"]),
        .executableTarget(name: "swiftcode-simd", dependencies: ["SwiftCodeRelease", "SwiftCodeHypervisor", "SwiftCodeDarwinABI", "SwiftCodeDarwinKernel", "SwiftCodeMachO", "SwiftCodeXPC", "SwiftCodeHostServices", "SwiftCodeMetalHost", "SwiftCodeVulkan", "SwiftCodeDisplayStream", "CSwiftCodeCodec", "CSwiftCodeVideo", "SwiftCodeSimFeatures", "SwiftCodeHealthStore", "SwiftCodeProfiler", "SwiftCodeDebug", "SwiftCodeXRReprojection"]),
        .executableTarget(name: "swiftcode", dependencies: ["SwiftCodeRelease", "SwiftCodePlist", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodeMachO", "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodePreviews", "SwiftCodeProfiler", "SwiftCodeBuildServer", "SwiftCodeXcodebuild", "SwiftCodeAssetCatalog", "SwiftCodeIDECore", "SwiftCodeStrings", "SwiftCodeSimLink", "SwiftCodeCompletion"]),
        // IDE (specs/ide/): build engines and the debug-adapter client
        // Subprocess runs and the debug-build main-thread guard.
        .target(name: "SwiftCodeSubprocess"),
        .testTarget(name: "SwiftCodeSubprocessTests", dependencies: ["SwiftCodeSubprocess"]),
        // The coding assistant's model providers, conversations and prompts (specs/ide/coding-assistant.md)
        .target(name: "SwiftCodeAssistant", dependencies: ["SwiftCodeSubprocess", "SwiftCodeBuild", .product(name: "Crypto", package: "swift-crypto")], resources: [.copy("Resources/System Assets"), .copy("Resources/SDKHosts"), .copy("Resources/ReverseBridge.mjs")]),
        .testTarget(name: "SwiftCodeAssistantTests", dependencies: ["SwiftCodeAssistant", "SwiftCodeSubprocess"]),
        // GitHub: the api.github.com client shared by the assistant's
        // GitHub tools and the settings pane.
        .target(name: "SwiftCodeGitHub"),
        .testTarget(name: "SwiftCodeGitHubTests", dependencies: ["SwiftCodeGitHub"]),
        // Extensions v2 platform (specs/ide/extensions-platform.md §10.10):
        // SwiftCodeGitHub model — plain .target, library product, test target.
        .target(name: "SwiftCodeExtensions", dependencies: ["SwiftCodeSubprocess", "SwiftCodeLanguage", "SwiftCodeDebug"],
                resources: [.copy("Resources/extension-host.js")]),
        .testTarget(name: "SwiftCodeExtensionsTests", dependencies: ["SwiftCodeExtensions"]),
        // Cloud accounts and auth (specs/ide/cloud-accounts.md §1):
        // a URLSession REST client for Appwrite, no third-party
        // dependency. Depends on SwiftCodeAssistant only for SecretStore.
        .target(name: "SwiftCodeCloud", dependencies: ["SwiftCodeAssistant"]),
        .testTarget(name: "SwiftCodeCloudTests", dependencies: ["SwiftCodeCloud", "SwiftCodeAssistant"]),
        // Google account auth (specs/ide/cloud-accounts.md §10).
        .target(name: "SwiftCodeGoogleAuth", dependencies: ["SwiftCodeAssistant", .product(name: "Crypto", package: "swift-crypto")], resources: [.copy("Resources/GoogleCloudSDK")]),
        .testTarget(name: "SwiftCodeGoogleAuthTests", dependencies: ["SwiftCodeGoogleAuth", "SwiftCodeAssistant"]),
        // Paywall / entitlement runtime (specs/ide/storekit-paywall.md):
        // Apple StoreKit 2 only (behind `#if canImport(StoreKit)`),
        // no third-party dependency.
        .target(name: "SwiftCodePaywall"),
        .testTarget(name: "SwiftCodePaywallTests", dependencies: ["SwiftCodePaywall"]),
        // SDK platform (specs/ide/sdk-platform.md): Legacy's SwiftCode/SDK.
        // SwiftCodeSDK is the host platform (contracts, kits, host, runtime);
        // SwiftCodeSDKStudio holds the Studio UI models separately because
        // they need SwiftCodeSDK and SwiftCodeExtensions both, which would be a
        // dependency cycle inside a single target.
        .target(name: "SwiftCodeSDK", dependencies: ["SwiftCodeExtensions", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeBuild", "SwiftCodeIDECore",
                                                 .product(name: "Crypto", package: "swift-crypto")],
                resources: [.copy("Resources/SwiftCodeSDK.json")]),
        .target(name: "SwiftCodeSDKStudio", dependencies: ["SwiftCodeSDK", "SwiftCodeExtensions"]),
        .testTarget(name: "SwiftCodeSDKTests", dependencies: ["SwiftCodeSDK", "SwiftCodeExtensions", "SwiftCodeSDKStudio", "SwiftCodeAssistant"]),
        // The `swiftcode` CLI and SDK tools (Legacy SwiftCode/SDK/Sources/):
        // thin wrappers over SwiftCodeSDK entry points; no `sdk-test-runner`
        // product — Legacy's hand-rolled runner is superseded by `swift test`.
        .executableTarget(name: "SwiftCodeSDKCLI", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKProjectGenerator", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKProjectInspector", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKExtensionValidator", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKDiagnostics", dependencies: ["SwiftCodeSDK"]),
        .executableTarget(name: "SwiftCodeSDKDocumentationIndexer", dependencies: ["SwiftCodeSDK"]),
        // Predictive code completion: context, backends (Ollama, llama-server, OpenAI-compatible), shaping, the editor session (specs/ide/predictive-completion.md)
        .target(name: "SwiftCodeCompletion", dependencies: ["SwiftCodeAssistant"]),
        .testTarget(name: "SwiftCodeCompletionTests", dependencies: ["SwiftCodeCompletion", "SwiftCodeAssistant"]),
        .target(name: "SwiftCodeBuild", dependencies: ["SwiftCodeProject", "SwiftCodePlist", "SwiftCodeWorkspace", "SwiftCodeSubprocess"]),
        .target(name: "SwiftCodeDebug", dependencies: ["SwiftCodeSubprocess"]),
        .testTarget(name: "SwiftCodeBuildTests", dependencies: ["SwiftCodeBuild"]),
        // Previews (specs/ide/previews.md): discovery, payload and host generation, the update planner, the screen layout
        .target(name: "SwiftCodePreviews", dependencies: ["SwiftCodeBuild", "SwiftCodeSubprocess"]),
        .testTarget(name: "SwiftCodePreviewsTests", dependencies: ["SwiftCodePreviews"]),
        .testTarget(name: "SwiftCodeDebugTests", dependencies: ["SwiftCodeDebug"]),
        // Language services (specs/ide/language.md): LSP client for sourcekit-lsp
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
        // The portable viewer: stream client, canvas, touches, layout, scripts (display-stream.md §13)
        .target(name: "SwiftCodeRemoteViewer", dependencies: ["SwiftCodeDisplayStream", "CSwiftCodeCodec", "CSwiftCodeVideo", "SwiftCodeDeviceModel"]),
        .testTarget(name: "SwiftCodeRemoteViewerTests", dependencies: ["SwiftCodeRemoteViewer", "SwiftCodeDisplayStream", "SwiftCodeDeviceModel", "CSwiftCodeCodec"]),
    ]
)

// The release's version (swiftcode/VERSION is the source of truth); every shipped tool's `--version`.
package.targets += [
    .target(name: "SwiftCodeRelease"),
    .testTarget(name: "SwiftCodeReleaseTests", dependencies: ["SwiftCodeRelease"]),
]

// The AppKit shell and app exist only on macOS.
#if os(macOS)
package.products += [.executable(name: "SwiftCodeApp", targets: ["SwiftCodeApp"]),
                     .executable(name: "swiftcode-sim-viewer", targets: ["swiftcode-sim-viewer"]),
                     // The agent swiftcodebuild inserts into a test host app (specs/ide/testing.md, "SwiftCode implementation").
                     // SimGuestAgents/build-test-agent.sh builds the same sources for the iOS simulator.
                     .library(name: "SwiftCodeTestAgent", type: .dynamic, targets: ["SwiftCodeTestAgent", "CSwiftCodeTestAgentLoader"]),
                     // Bulk wave: Legacy's Connect (Bonjour/Network) and
                     // Collaboration (MultipeerConnectivity) families.
                     // macOS-only (Network, MultipeerConnectivity).
                     .library(name: "SwiftCodeConnect", targets: ["SwiftCodeConnect"]),
                     .library(name: "SwiftCodeCollaboration", targets: ["SwiftCodeCollaboration"])]
package.targets += [
    .target(name: "CSwiftCodeTestAgentLoader"),
    .target(name: "SwiftCodeTestAgent"),
    // Bulk wave: Legacy's Connect family (Bonjour/Network, iOS<->Mac
    // pairing over the local network). macOS-only.
    .target(name: "SwiftCodeConnect", dependencies: ["SwiftCodeAssistant"]),
    .testTarget(name: "SwiftCodeConnectTests", dependencies: ["SwiftCodeConnect"]),
    // Bulk wave: Legacy's Collaboration family (MultipeerConnectivity
    // sessions, shared workspaces, transfers). macOS-only. Imports
    // CryptoKit directly; no swift-crypto dep (that product is for
    // Linux-portable targets importing `Crypto`).
    .target(name: "SwiftCodeCollaboration"),
    .testTarget(name: "SwiftCodeCollaborationTests", dependencies: ["SwiftCodeCollaboration"]),
    // The simulator viewer (display-stream.md; scripts/swiftcode-sim-try)
    // The device windows (compact window, canvas, frame, controls; specs/ide/device-hub.md), shared by the viewer and the IDE
    .target(name: "SwiftCodeDeviceUI", dependencies: ["SwiftCodeDisplayStream", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel"]),
    .testTarget(name: "SwiftCodeDeviceUITests", dependencies: ["SwiftCodeDeviceUI", "SwiftCodeDeviceModel", "SwiftCodeDisplayStream"]),
    .executableTarget(name: "swiftcode-sim-viewer", dependencies: ["SwiftCodeRelease", "SwiftCodeDisplayStream", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel", "SwiftCodeDeviceUI", "SwiftCodeRemoteViewer", "SwiftCodeSimLink"]),
    .target(name: "SwiftCodeUI", dependencies: ["SwiftCodeMCP", "SwiftCodeIDECore", "SwiftCodeCompletion", "SwiftCodePreviews", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeGitHub", "SwiftCodeExtensions", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel", "SwiftCodeDeviceUI", "SwiftCodeProfiler", "SwiftCodeCloud", "SwiftCodeGoogleAuth", "SwiftCodePaywall", "SwiftCodeSDK", "SwiftCodeHealthStore", "SwiftCodeIDEShell",
                                             // Bulk wave: Connect + Collaboration families.
                                             "SwiftCodeConnect", "SwiftCodeCollaboration",
                                             // Gap-closure: the VM console (VirtualMachineRegistry)
                                             // probes KVM through SwiftCodeHypervisor.
                                             "SwiftCodeHypervisor",
                                             // The StoreKit editor controller (specs/ide/storekit-paywall.md).
                                             .product(name: "StoreKitConfiguration", package: "storekit"), .product(name: "Markdown", package: "swift-markdown")], resources: [.copy("Resources/Sounds")]),
    .executableTarget(name: "SwiftCodeApp", dependencies: ["SwiftCodeRelease", "SwiftCodeUI"]),
    .testTarget(name: "SwiftCodeUITests", dependencies: ["SwiftCodeMCP", "SwiftCodeUI", "SwiftCodeIDECore", "SwiftCodeCompletion", "SwiftCodePreviews", "SwiftCodeDisplayStream", "SwiftCodeSimFeatures", "SwiftCodeDeviceModel", "SwiftCodeDeviceUI", "SwiftCodeBuild", "SwiftCodeDebug", "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeExtensions", "SwiftCodeProfiler", "SwiftCodeBuildServer", "SwiftCodeIDEShell", "SwiftCodeCloud", "SwiftCodeGoogleAuth", "SwiftCodeSDK"]),
]
#else
// The Linux viewer: an SDL 3 window (loaded at run time) on the portable viewer (display-stream.md §13).
package.products += [.executable(name: "swiftcode-sim-viewer", targets: ["swiftcode-sim-viewer"]),
                     .library(name: "SwiftCodeRemoteViewerSDL", targets: ["SwiftCodeRemoteViewerSDL"])]
package.targets += [
    .target(name: "SwiftCodeRemoteViewerSDL", dependencies: ["SwiftCodeRemoteViewer", "SwiftCodeDisplayStream", "SwiftCodeDeviceModel", "SwiftCodeSimLink"],
            linkerSettings: [.linkedLibrary("dl")]),
    .executableTarget(name: "swiftcode-sim-viewer", dependencies: ["SwiftCodeRelease", "SwiftCodeRemoteViewerSDL", "SwiftCodeRemoteViewer", "SwiftCodeDisplayStream"]),
]
#endif

// The simulator link (specs/simulator/sim-link.md): SwiftCode's own authenticated,
// encrypted connection between a client (the IDE, the viewer, `swiftcode sim
// remote`) and a simulator host's `swiftcode-simhost`: Noise XX handshakes with
// pinned Ed25519 identities, pairing codes, the control protocol, uploads and
// the UDP media channel. Cryptography from swift-crypto (Apache-2.0).
package.dependencies += [.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")]
package.products += [.library(name: "SwiftCodeSimLink", targets: ["SwiftCodeSimLink"]),
                     .executable(name: "swiftcode-simhost", targets: ["swiftcode-simhost"])]
package.targets += [
    .target(name: "SwiftCodeSimLink", dependencies: ["SwiftCodeDisplayStream", .product(name: "Crypto", package: "swift-crypto")]),
    .testTarget(name: "SwiftCodeSimLinkTests", dependencies: ["SwiftCodeSimLink", "SwiftCodeDisplayStream"]),
    .executableTarget(name: "swiftcode-simhost", dependencies: ["SwiftCodeRelease", "SwiftCodeSimLink"]),
]

// The headset viewer (specs/simulator/xr-viewer.md): a visionOS device in an
// OpenXR headset. CSwiftCodeOpenXR opens the Khronos OpenXR loader and the Vulkan
// loader at run time (headers vendored: OpenXR-SDK 1.1.47, Apache-2.0 OR MIT;
// the CVulkan target's Vulkan headers); no runtime is linked. On macOS it
// builds as stubs and the viewer reports that OpenXR is not offered.
package.products += [.executable(name: "swiftcode-xr-viewer", targets: ["swiftcode-xr-viewer"])]
package.targets += [
    .target(name: "CSwiftCodeOpenXR", exclude: ["openxr/LICENSE"], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
    .target(name: "SwiftCodeXRViewer", dependencies: ["CSwiftCodeOpenXR", "CSwiftCodeVideo", "CSwiftCodeCodec", "SwiftCodeDisplayStream", "SwiftCodeRemoteViewer", "SwiftCodeXRReprojection"]),
    .executableTarget(name: "swiftcode-xr-viewer", dependencies: ["SwiftCodeRelease", "SwiftCodeXRViewer", "SwiftCodeSimLink", "SwiftCodeDisplayStream"]),
    .testTarget(name: "SwiftCodeXRViewerTests", dependencies: ["SwiftCodeXRViewer", "SwiftCodeDisplayStream", "SwiftCodeRemoteViewer", "CSwiftCodeCodec", "CSwiftCodeOpenXR", "CSwiftCodeVideo"]),
]

// Depth re-projection for the headset viewer (specs/simulator/xr-depth.md):
// the depth codec, the re-projection math, the CPU reference warp and, in
// CSwiftCodeXRReprojection, the GPU path (Vulkan through vkGetInstanceProcAddr on
// the viewer's OpenXR device, or a device of its own for tests; SwiftCode's own
// GLSL, compiled once to SPIR-V by scripts/xr-depth-shaders.sh). Builds and
// tests everywhere; the GPU tests run where a Vulkan loader is installed.
package.targets += [
    .target(name: "CSwiftCodeXRReprojection", exclude: ["shaders"], linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux])), .linkedLibrary("pthread", .when(platforms: [.linux]))]),
    .target(name: "SwiftCodeXRReprojection", dependencies: ["CSwiftCodeXRReprojection", "CSwiftCodeCodec", "SwiftCodeDisplayStream"]),
    .testTarget(name: "SwiftCodeXRReprojectionTests", dependencies: ["SwiftCodeXRReprojection", "SwiftCodeDisplayStream", "CSwiftCodeVideo"]),
]

// The editor's portable syntax layer (specs/ide/source-editor.md, "SwiftCode
// implementation"): highlighting tokens for Swift (swift-syntax's parser,
// Apache-2.0) and hand-written line lexers for the other languages, the
// incremental highlighter, the bracket structure and the typing rules.
// Builds and tests on macOS and Linux; SwiftCodeIDECore and the editors use it.
package.dependencies += [.package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0")]

// The Markdown renderer (specs/ide/wave19-views.md): SwiftCodeUI's
// MarkdownRenderer renders Legacy's Markdown files with swift-markdown's
// Document/MarkupVisitor API (Apache-2.0).
package.dependencies += [.package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0")]

// The StoreKit configuration file model (specs/ide/storekit-paywall.md
// §8.1): frameworks/storekit is a sibling package in this repo. The
// .storekit editor model in SwiftCodeIDECore reads/writes real .storekit
// files through its StoreKitConfiguration product instead of a second
// parser. Unconditional path dependency: a checkout without
// frameworks/storekit next to swiftcode/ cannot build the new editor
// files, so the Linux rsync workflow in AGENTS.md syncs it too.
// Only StoreKitConfiguration is used — never the package's `StoreKit`
// product, which re-implements Apple's StoreKit API under the same
// module name and would shadow it.
package.dependencies += [.package(path: "../frameworks/storekit")]
package.products += [.library(name: "SwiftCodeSyntax", targets: ["SwiftCodeSyntax"])]
package.targets += [
    .target(name: "SwiftCodeSyntax", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                                                .product(name: "SwiftParser", package: "swift-syntax"),
                                                .product(name: "SwiftIDEUtils", package: "swift-syntax")]),
    .testTarget(name: "SwiftCodeSyntaxTests", dependencies: ["SwiftCodeSyntax"]),
    // Highlighting and typing measurements (build it in release).
    .executableTarget(name: "swiftcode-syntax-bench", dependencies: ["SwiftCodeSyntax"]),
]

// The IDE's portable core (docs/PARITY.md §5, milestone L0): the model
// shared by the macOS AppKit shell and the Linux SwiftUI shell. Builds and
// tests on macOS and Linux; SwiftCodeUI re-exports it.
package.targets += [
    .target(name: "SwiftCodeIDECore", dependencies: ["SwiftCodeRelease", "SwiftCodeSyntax", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodePlist", "SwiftCodeBuild", "SwiftCodeDebug",
                                                 "SwiftCodeLanguage", "SwiftCodeXcodebuild", "SwiftCodeSubprocess", "SwiftCodeAssistant", "SwiftCodeCompletion", "SwiftCodeProfiler",
                                                 "SwiftCodePreviews", "SwiftCodeDeviceModel", "SwiftCodeSimFeatures", "SwiftCodeStrings", "SwiftCodeSigning",
                                                 // The .storekit editor model (specs/ide/storekit-paywall.md):
                                                 // reads/writes real .storekit files through the
                                                 // framework model instead of a second parser.
                                                 .product(name: "StoreKitConfiguration", package: "storekit"),
                                                 // Gap-closure: the AppTestStore-backed StoreKit
                                                 // simulation (StoreKitSimulationSession) and the
                                                 // SQLite/database models read the HealthStore.
                                                 .product(name: "StoreKitEngine", package: "storekit"),
                                                 "SwiftCodeHealthStore",
                                                 // SHA-256 and the asset service's ES256 chain (runtime downloads, route B).
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

// App icons and compiled asset catalogs (specs/formats/README-icon.md): the
// .icon document model, and the Assets.car writer, reader and compiler.
// Portable (Foundation only).
package.products += [.library(name: "SwiftCodeIcon", targets: ["SwiftCodeIcon"]),
                     .library(name: "SwiftCodeAssetCatalog", targets: ["SwiftCodeAssetCatalog"])]
package.targets += [
    .target(name: "SwiftCodeIcon"),
    .target(name: "SwiftCodeAssetCatalog", dependencies: ["SwiftCodeIcon"]),
    .testTarget(name: "SwiftCodeIconTests", dependencies: ["SwiftCodeIcon"]),
    .testTarget(name: "SwiftCodeAssetCatalogTests", dependencies: ["SwiftCodeAssetCatalog", "SwiftCodeIcon"]),
]

// String Catalogs (specs/ide/string-catalog.md, "SwiftCode implementation"): the
// catalog model, the compiler to .strings/.stringsdict (`swiftcode strings
// compile`, also swift-build's `xcstringstool`), extraction from Swift
// (swift-syntax) and Objective-C sources, merging, and conversion of
// .strings/.stringsdict tables. Portable (macOS and Linux).
package.products += [.library(name: "SwiftCodeStrings", targets: ["SwiftCodeStrings"])]
package.targets += [
    .target(name: "SwiftCodeStrings", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax"),
                                                 .product(name: "SwiftParser", package: "swift-syntax")]),
    .testTarget(name: "SwiftCodeStringsTests", dependencies: ["SwiftCodeStrings"]),
]

// swiftcodebuild: an xcodebuild-compatible command line (specs/xcodebuild/).
package.products += [.executable(name: "swiftcodebuild", targets: ["swiftcodebuild-cli"]),
                     .library(name: "SwiftCodeBuildServer", targets: ["SwiftCodeBuildServer"]),
                     .executable(name: "swiftcode-bsp", targets: ["swiftcode-bsp"])]
package.targets += [
    // Code signing (specs/ide/signing.md): Foundation only, because swiftcode-swb compiles the same sources.
    .target(name: "SwiftCodeSigning"),
    .testTarget(name: "SwiftCodeSigningTests", dependencies: ["SwiftCodeSigning"]),
    .target(name: "SwiftCodeXcodebuild", dependencies: ["SwiftCodeRelease", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodePlist", "SwiftCodeBuild", "SwiftCodeSubprocess", "SwiftCodeSigning"]),
    // Target and directory are not named "swiftcodebuild": that collides with SwiftCodeBuild on case-insensitive file systems.
    .executableTarget(name: "swiftcodebuild-cli", dependencies: ["SwiftCodeRelease", "SwiftCodeXcodebuild"], path: "Sources/swiftcodebuild-cli"),
    .testTarget(name: "SwiftCodeXcodebuildTests", dependencies: ["SwiftCodeXcodebuild", "SwiftCodeProject"]),
    // The build server sourcekit-lsp asks for compiler arguments in projects and workspaces (specs/ide/language.md §BSP)
    .target(name: "SwiftCodeBuildServer", dependencies: ["SwiftCodeXcodebuild", "SwiftCodeBuild", "SwiftCodeProject", "SwiftCodeWorkspace", "SwiftCodeSettings", "SwiftCodeDebug", "SwiftCodeSubprocess"]),
    .executableTarget(name: "swiftcode-bsp", dependencies: ["SwiftCodeRelease", "SwiftCodeBuildServer"]),
    .testTarget(name: "SwiftCodeBuildServerTests", dependencies: ["SwiftCodeBuildServer", "SwiftCodeLanguage", "SwiftCodeDebug", "SwiftCodeXcodebuild", "swiftcode-bsp", "SwiftCodeIDECore",
                                                              "SwiftCodeSubprocess", "SwiftCodeWorkspace"]),
]

// The SwiftUI workspace shell (docs/PARITY.md §5, milestone L1).
// SwiftCodeIDEShell holds its view models (no toolkit, tested everywhere);
// swiftcode-ide holds the views and the app. On Linux the views build against
// OpenViews (frameworks/swiftui, SwiftCode's own SwiftUI: its `SwiftUI`
// module); they are left out when that folder is not next to this package
// (an rsync of swiftcode/ alone). On macOS they build against Apple's SwiftUI;
// the macOS product is still the AppKit SwiftCodeApp.
// SwiftCodeEditorKit is the source editor's model without a toolkit (docs/PARITY.md §5.9).
package.products += [.library(name: "SwiftCodeIDEShell", targets: ["SwiftCodeIDEShell"]), .library(name: "SwiftCodeEditorKit", targets: ["SwiftCodeEditorKit"])]
package.targets += [
    .target(name: "SwiftCodeEditorKit", dependencies: ["SwiftCodeSyntax"]),
    .testTarget(name: "SwiftCodeEditorKitTests", dependencies: ["SwiftCodeEditorKit", "SwiftCodeSyntax"]),
    .target(name: "SwiftCodeIDEShell", dependencies: ["SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeXcodebuild", "SwiftCodeSimLink", "SwiftCodeEditorKit", "SwiftCodeDebug", "SwiftCodeAssistant",
                                                  "SwiftCodePreviews", "SwiftCodeDeviceModel"]),
    .testTarget(name: "SwiftCodeIDEShellTests", dependencies: ["SwiftCodeIDEShell", "SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeEditorKit", "SwiftCodeCompletion", "SwiftCodeDebug", "SwiftCodeAssistant",
                                                          "SwiftCodePreviews"]),
]
// Agent mode (specs/ide/coding-assistant.md, "SwiftCode implementation"): the
// SwiftCode MCP server (`swiftcode mcp`, and in-process for the IDE's agents), the
// JSON-RPC layer it shares with the Agent Client Protocol client, and ACP
// agents as coding-assistant back ends. Portable (macOS and Linux).
package.products += [.library(name: "SwiftCodeMCP", targets: ["SwiftCodeMCP"])]
package.targets += [
    .target(name: "SwiftCodeMCP", dependencies: ["SwiftCodeIDECore", "SwiftCodeIDEShell", "SwiftCodeAssistant", "SwiftCodeCompletion", "SwiftCodeBuild", "SwiftCodePreviews",
                                             "SwiftCodeProject", "SwiftCodePlist", "SwiftCodeSettings", "SwiftCodeWorkspace", "SwiftCodeSubprocess", "SwiftCodeMachO", "SwiftCodeGitHub",
                                             "SwiftCodeExtensions",
                                             // Gap-closure: the AST inspector and the token-aware
                                             // rename engine parse with swift-syntax directly
                                             // (SwiftCodeSyntax exposes no parse tree).
                                             .product(name: "SwiftSyntax", package: "swift-syntax"),
                                             .product(name: "SwiftParser", package: "swift-syntax"),
                                             .product(name: "Crypto", package: "swift-crypto")],
            // Gap-closure: the Reverse bridge script is loaded at run
            // time through Bundle.module; without this resource the
            // whole SwiftCodeMCP target fails to compile.
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
                                                          // Bulk wave (Views-D): backups + PR views.
                                                          "SwiftCodeCloud", "SwiftCodeGitHub",
                                                          .product(name: "StoreKitConfiguration", package: "storekit"),
                                                          .product(name: "SwiftUI", package: "swiftcode-swiftui"),
                                                          .product(name: "OVPlatform", package: "swiftcode-swiftui"),
                                                          .product(name: "OVDBus", package: "swiftcode-swiftui"),
                                                          .product(name: "OVText", package: "swiftcode-swiftui"),
                                                          // Wave 19 slice C: ModernGroupBoxStyle lives in
                                                          // SwiftCodeUI and 15 DevTools views call it.
                                                          "SwiftCodeUI",
                                                          // Audit D: BuildingXcodeProject.swift names
                                                          // SwiftCodeDarwinKernel (Linux-guarded sources).
                                                          "SwiftCodeDarwinKernel"]),
    ]
}
#else
package.products += [.executable(name: "swiftcode-ide", targets: ["swiftcode-ide"])]
package.targets += [
    .executableTarget(name: "swiftcode-ide", dependencies: ["SwiftCodeRelease", "SwiftCodeIDEShell", "SwiftCodeIDECore", "SwiftCodeSyntax", "SwiftCodeBuild", "SwiftCodeEditorKit", "SwiftCodeCompletion", "SwiftCodeAssistant",
                                                      "SwiftCodePreviews", "SwiftCodeExtensions", "SwiftCodeSDK", "SwiftCodeSDKStudio", "SwiftCodePaywall",
                                                      // Bulk wave (Views-D): backups + PR views.
                                                      "SwiftCodeCloud", "SwiftCodeGitHub",
                                                      .product(name: "StoreKitConfiguration", package: "storekit"),
                                                      // Wave 19 slice C: ModernGroupBoxStyle lives in
                                                      // SwiftCodeUI and 15 DevTools views call it.
                                                      "SwiftCodeUI",
                                                      // Audit D: BuildingXcodeProject.swift names
                                                      // SwiftCodeDarwinKernel.
                                                      "SwiftCodeDarwinKernel"]),
]
#endif
