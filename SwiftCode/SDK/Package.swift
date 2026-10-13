// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftCodeSDK",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SwiftCodeSDK", targets: ["SwiftCodeSDK"]),
        .library(name: "ProjectKit", targets: ["ProjectKit"]),
        .library(name: "BuildKit", targets: ["BuildKit"]),
        .library(name: "SourceControlKit", targets: ["SourceControlKit"]),
        .library(name: "WorkspaceKit", targets: ["WorkspaceKit"]),
        .library(name: "DiagnosticsKit", targets: ["DiagnosticsKit"]),
        .library(name: "ExtensionKit", targets: ["ExtensionKit"]),
        .executable(name: "swiftcode-sdk", targets: ["CLI"]),
        .executable(name: "project-generator", targets: ["ProjectGenerator"]),
        .executable(name: "project-inspector", targets: ["ProjectInspector"]),
        .executable(name: "extension-validator", targets: ["ExtensionValidator"]),
        .executable(name: "diagnostics", targets: ["DiagnosticsTool"]),
        .executable(name: "documentation-indexer", targets: ["DocumentationIndexer"]),
        .executable(name: "sdk-test-runner", targets: ["SDKTestRunner"])
    ],
    targets: [
        .target(
            name: "DiagnosticsKit",
            dependencies: [],
            path: "Sources/DiagnosticsKit"
        ),
        .target(
            name: "WorkspaceKit",
            dependencies: ["DiagnosticsKit"],
            path: "Sources/WorkspaceKit"
        ),
        .target(
            name: "ProjectKit",
            dependencies: ["WorkspaceKit", "DiagnosticsKit"],
            path: "Sources/ProjectKit"
        ),
        .target(
            name: "BuildKit",
            dependencies: ["DiagnosticsKit", "WorkspaceKit"],
            path: "Sources/BuildKit"
        ),
        .target(
            name: "SourceControlKit",
            dependencies: ["DiagnosticsKit", "WorkspaceKit"],
            path: "Sources/SourceControlKit"
        ),
        .target(
            name: "ExtensionKit",
            dependencies: ["DiagnosticsKit", "WorkspaceKit"],
            path: "Sources/ExtensionKit"
        ),
        .target(
            name: "SwiftCodeSDK",
            dependencies: [
                "DiagnosticsKit",
                "WorkspaceKit",
                "ProjectKit",
                "BuildKit",
                "SourceControlKit",
                "ExtensionKit"
            ],
            path: "Sources/SwiftCodeSDK"
        ),
        .executableTarget(
            name: "CLI",
            dependencies: ["SwiftCodeSDK"],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "ProjectGenerator",
            dependencies: ["ProjectKit", "SwiftCodeSDK"],
            path: "Sources/Tools/ProjectGenerator"
        ),
        .executableTarget(
            name: "ProjectInspector",
            dependencies: ["ProjectKit", "SwiftCodeSDK"],
            path: "Sources/Tools/ProjectInspector"
        ),
        .executableTarget(
            name: "ExtensionValidator",
            dependencies: ["ExtensionKit", "SwiftCodeSDK"],
            path: "Sources/Tools/ExtensionValidator"
        ),
        .executableTarget(
            name: "DiagnosticsTool",
            dependencies: ["DiagnosticsKit", "SwiftCodeSDK"],
            path: "Sources/Tools/DiagnosticsTool"
        ),
        .executableTarget(
            name: "DocumentationIndexer",
            dependencies: ["WorkspaceKit", "SwiftCodeSDK"],
            path: "Sources/Tools/DocumentationIndexer"
        ),
        .executableTarget(
            name: "SDKTestRunner",
            dependencies: ["SwiftCodeSDK"],
            path: "Tests/SDKTestRunner"
        )
    ]
)
