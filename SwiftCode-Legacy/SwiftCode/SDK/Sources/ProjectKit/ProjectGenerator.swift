import Foundation
import DiagnosticsKit
import WorkspaceKit

public struct ProjectGeneratorOptions: Sendable {
    public let type: ProjectType
    public let name: String
    public let identifier: String
    public let destinationDirectory: String
    public let author: String?

    public init(
        type: ProjectType,
        name: String,
        identifier: String,
        destinationDirectory: String,
        author: String? = nil
    ) {
        self.type = type
        self.name = name
        self.identifier = identifier
        self.destinationDirectory = destinationDirectory
        self.author = author
    }
}

public final class ProjectGenerator: Sendable {
    public init() {}

    public func generate(options: ProjectGeneratorOptions) throws -> ProjectMetadata {
        let ws = Workspace(path: options.destinationDirectory)
        let fileAccess = ws.fileAccess

        switch options.type {
        case .swiftPackage:
            try generateSwiftPackage(options: options, fileAccess: fileAccess)
        case .typescriptExtension, .swiftcodeExtension:
            try generateTypeScriptExtension(options: options, fileAccess: fileAccess)
        case .automationExtension:
            try generateAutomationExtension(options: options, fileAccess: fileAccess)
        case .sourceControlExtension:
            try generateSourceControlExtension(options: options, fileAccess: fileAccess)
        case .macosApp:
            try generateMacOSApp(options: options, fileAccess: fileAccess)
        case .xcodeProject:
            try generateMacOSApp(options: options, fileAccess: fileAccess)
        }

        let inspector = ProjectInspector()
        return try inspector.inspect(at: options.destinationDirectory)
    }

    private func generateSwiftPackage(options: ProjectGeneratorOptions, fileAccess: SafeFileAccess) throws {
        let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(options.name)",
            platforms: [
                .macOS(.v14)
            ],
            products: [
                .library(name: "\(options.name)", targets: ["\(options.name)"])
            ],
            dependencies: [],
            targets: [
                .target(
                    name: "\(options.name)",
                    dependencies: []
                ),
                .testTarget(
                    name: "\(options.name)Tests",
                    dependencies: ["\(options.name)"]
                )
            ]
        )
        """
        try fileAccess.writeString(manifest, to: "Package.swift")

        let source = """
        import Foundation

        public struct \(options.name) {
            public var text = "Hello from \(options.name)!"

            public init() {}
        }
        """
        try fileAccess.writeString(source, to: "Sources/\(options.name)/\(options.name).swift")

        let test = """
        import Testing
        @testable import \(options.name)

        @Test func example() async throws {
            let instance = \(options.name)()
            #expect(instance.text.contains("Hello"))
        }
        """
        try fileAccess.writeString(test, to: "Tests/\(options.name)Tests/\(options.name)Tests.swift")

        let readme = """
        # \(options.name)

        A Swift package created with SwiftCode SDK.
        """
        try fileAccess.writeString(readme, to: "README.md")
    }

    private func generateTypeScriptExtension(options: ProjectGeneratorOptions, fileAccess: SafeFileAccess) throws {
        let manifest = """
        {
          "manifestVersion": 1,
          "id": "\(options.identifier)",
          "name": "\(options.name)",
          "version": "0.1.0",
          "description": "\(options.name) built with SwiftCode SDK",
          "type": "extension",
          "runtime": {
            "language": "typescript",
            "entrypoint": "dist/index.js",
            "minimumSwiftCodeVersion": "1.0.0"
          },
          "sdk": {
            "name": "@swiftcode/sdk",
            "versionRange": "^1.0.0",
            "protocolVersion": 1
          },
          "capabilities": [
            {
              "id": "ui.contribute",
              "reason": "Registers toolbar actions and UI commands"
            }
          ],
          "contributes": {
            "commands": [
              {
                "id": "\(options.identifier).hello",
                "title": "Say Hello"
              }
            ]
          }
        }
        """
        try fileAccess.writeString(manifest, to: "swiftcode.json")

        let packageJson = """
        {
          "name": "\(options.name.lowercased())",
          "version": "0.1.0",
          "description": "\(options.name) SwiftCode extension",
          "main": "dist/index.js",
          "scripts": {
            "build": "tsc"
          },
          "devDependencies": {
            "@swiftcode/sdk": "^1.0.0",
            "typescript": "^5.0.0"
          }
        }
        """
        try fileAccess.writeString(packageJson, to: "package.json")

        let tsconfig = """
        {
          "compilerOptions": {
            "target": "ES2022",
            "module": "NodeNext",
            "moduleResolution": "NodeNext",
            "outDir": "dist",
            "rootDir": "src",
            "strict": true,
            "skipLibCheck": true
          },
          "include": ["src/**/*"]
        }
        """
        try fileAccess.writeString(tsconfig, to: "tsconfig.json")

        let indexTs = """
        import { ExtensionContext } from '@swiftcode/sdk';

        export function activate(context: ExtensionContext) {
          context.commands.register('\(options.identifier).hello', async () => {
            console.log('Hello from \(options.name)!');
          });
        }

        export function deactivate() {
          console.log('Deactivated \(options.name)');
        }
        """
        try fileAccess.writeString(indexTs, to: "src/index.ts")

        let readme = """
        # \(options.name)

        SwiftCode TypeScript Extension.
        """
        try fileAccess.writeString(readme, to: "README.md")
    }

    private func generateAutomationExtension(options: ProjectGeneratorOptions, fileAccess: SafeFileAccess) throws {
        let manifest = """
        {
          "manifestVersion": 1,
          "id": "\(options.identifier)",
          "name": "\(options.name)",
          "version": "0.1.0",
          "description": "Workflow automation extension for SwiftCode",
          "type": "extension",
          "runtime": {
            "language": "typescript",
            "entrypoint": "dist/index.js",
            "minimumSwiftCodeVersion": "1.0.0"
          },
          "sdk": {
            "name": "@swiftcode/sdk",
            "versionRange": "^1.0.0",
            "protocolVersion": 1
          },
          "capabilities": [
            {
              "id": "project.read",
              "reason": "Inspects project structure for automated pipelines"
            },
            {
              "id": "build.execute",
              "reason": "Triggers automated build verification"
            }
          ],
          "contributes": {
            "commands": [
              {
                "id": "\(options.identifier).automate",
                "title": "Run Automation Pipeline"
              }
            ]
          }
        }
        """
        try fileAccess.writeString(manifest, to: "swiftcode.json")

        let source = """
        export function activate(context: any) {
          context.commands.register('\(options.identifier).automate', async () => {
            const project = await context.project.getCurrent();
            console.log('Automating project:', project.name);
          });
        }
        """
        try fileAccess.writeString(source, to: "src/index.ts")
    }

    private func generateSourceControlExtension(options: ProjectGeneratorOptions, fileAccess: SafeFileAccess) throws {
        let manifest = """
        {
          "manifestVersion": 1,
          "id": "\(options.identifier)",
          "name": "\(options.name)",
          "version": "0.1.0",
          "description": "Source control management extension for SwiftCode",
          "type": "extension",
          "runtime": {
            "language": "typescript",
            "entrypoint": "dist/index.js",
            "minimumSwiftCodeVersion": "1.0.0"
          },
          "sdk": {
            "name": "@swiftcode/sdk",
            "versionRange": "^1.0.0",
            "protocolVersion": 1
          },
          "capabilities": [
            {
              "id": "source-control.read",
              "reason": "Monitors git status and repository diffs"
            }
          ],
          "contributes": {
            "commands": [
              {
                "id": "\(options.identifier).status",
                "title": "Inspect Git Status"
              }
            ]
          }
        }
        """
        try fileAccess.writeString(manifest, to: "swiftcode.json")

        let source = """
        export function activate(context: any) {
          context.commands.register('\(options.identifier).status', async () => {
            const status = await context.sourceControl.getStatus();
            console.log('Current branch:', status.currentBranch);
          });
        }
        """
        try fileAccess.writeString(source, to: "src/index.ts")
    }

    private func generateMacOSApp(options: ProjectGeneratorOptions, fileAccess: SafeFileAccess) throws {
        let manifest = """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "\(options.name)",
            platforms: [
                .macOS(.v14)
            ],
            products: [
                .executable(name: "\(options.name)", targets: ["\(options.name)"])
            ],
            dependencies: [],
            targets: [
                .executableTarget(
                    name: "\(options.name)",
                    dependencies: []
                )
            ]
        )
        """
        try fileAccess.writeString(manifest, to: "Package.swift")

        let source = """
        import SwiftUI

        @main
        struct \(options.name)App: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }

        struct ContentView: View {
            var body: some View {
                VStack(spacing: 20) {
                    Image(systemName: "globe")
                        .imageScale(.large)
                    Text("Hello from \(options.name)!")
                        .font(.title)
                }
                .padding(40)
            }
        }
        """
        try fileAccess.writeString(source, to: "Sources/\(options.name)/main.swift")
    }
}
