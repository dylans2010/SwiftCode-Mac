import Foundation

/// The `swiftcode-sdk` command-line interface, as a library entry point.
///
/// Legacy's `CLI/main.swift` was an `@main` struct that called `exit()`.
/// An executable target cannot live inside the `YcodeSDK` library, so this
/// port keeps the identical command set and output, but as
/// `run(arguments:) async -> Int32`: the executable target (see the
/// Package.swift wiring note) wraps it in a thin `@main` that calls
/// `exit(SwiftCodeSDKCLI.run(...))`.
///
/// Commands: doctor, init, validate, build, test, inspect, package,
/// verify, docs. `--version` / `-v`, `--help` / `-h`.
///
/// Known Legacy defect, ported faithfully and NOT silently fixed: `test`
/// builds a `BuildConfig` whose `additionalArguments` are `["test",
/// "--disable-sandbox"]`, which `BuildService` appends *after* the
/// `swift build …` arguments, producing `swift build … test
/// --disable-sandbox` — `swift build` takes no such positional. The
/// correct invocation is `swift test …`. Fix in the build slice; see the
/// wave-14 slice spec draft.
public enum SwiftCodeSDKCLI {
    public static func run(arguments: [String]) async -> Int32 {
        let args = arguments

        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            printHelp()
            return 0
        }

        if args.contains("--version") || args.contains("-v") {
            print("swiftcode-sdk version \(SDKVersion.current)")
            return 0
        }

        let command = args[0]
        let subArgs = Array(args.dropFirst())

        let coordinator = SwiftCodeSDKCoordinator()

        do {
            switch command {
            case "doctor":
                return try runDoctor(coordinator: coordinator, args: subArgs)
            case "init":
                return try runInit(coordinator: coordinator, args: subArgs)
            case "validate":
                return try runValidate(coordinator: coordinator, args: subArgs)
            case "build":
                return try await runBuild(coordinator: coordinator, args: subArgs)
            case "test":
                return try await runTest(coordinator: coordinator, args: subArgs)
            case "inspect":
                return try runInspect(coordinator: coordinator, args: subArgs)
            case "package":
                return try runPackage(coordinator: coordinator, args: subArgs)
            case "verify":
                return try runVerify(coordinator: coordinator, args: subArgs)
            case "docs":
                return try runDocs(coordinator: coordinator, args: subArgs)
            default:
                print("Error: Unknown command '\(command)'")
                print("Run 'swiftcode-sdk --help' for available commands.")
                return 1
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            return 1
        }
    }

    public static func printHelp() {
        print("""
        OVERVIEW: SwiftCode SDK Command Line Interface
        Version: \(SDKVersion.current)

        USAGE: swiftcode-sdk <command> [options]

        COMMANDS:
          doctor           Inspect SDK installation, developer tools, and host environment
          init <type>      Initialize a new project or extension from a template
          validate <path>  Validate an extension manifest, project, or package
          build [path]     Execute project or extension build with diagnostic reporting
          test [path]      Run tests for a project or extension
          inspect <path>   Inspect project, extension, or package metadata
          package <path>   Package an extension into a .swiftcode-extension archive
          verify <path>    Verify integrity and signature of a package archive
          docs             Display or export offline SDK documentation
          --version, -v    Display SDK version
          --help, -h       Display this help information

        EXAMPLES:
          swiftcode-sdk doctor
          swiftcode-sdk init typescript-extension MyExtension --out ./MyExtension
          swiftcode-sdk validate ./MyExtension
          swiftcode-sdk build ./MyExtension
          swiftcode-sdk package ./MyExtension --out ./dist
          swiftcode-sdk verify ./dist/com.example.myext-1.0.0.swiftcode-extension
        """)
    }

    static func runDoctor(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        print("=== SwiftCode SDK Doctor ===")
        let report = coordinator.doctor.diagnose()
        print("OS: \(report.osVersion)")
        print("Architecture: \(report.architecture)")
        print("SDK Root: \(report.sdkRoot) [\(report.sdkRootExists ? "Found" : "Missing")]")
        print("\nDeveloper Tools:")
        for tool in report.tools {
            let status = tool.available ? "✅ \(tool.path) (\(tool.version ?? "available"))" : "❌ Not found"
            print("  - \(tool.name): \(status)")
        }

        if !report.diagnostics.isEmpty {
            print("\nDiagnostics:")
            print(DiagnosticFormatter.formatText(report.diagnostics))
        }

        if report.isHealthy {
            print("\nResult: SDK environment is healthy and ready for development.")
            return 0
        } else {
            print("\nResult: Environment has issues that need attention.")
            return 1
        }
    }

    static func runInit(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        guard !args.isEmpty else {
            print("Error: Missing project type.")
            print("Available types: swift-package, macos-app, typescript-extension, automation-extension, source-control-extension")
            return 1
        }

        let typeRaw = args[0]
        guard let type = ProjectType(rawValue: typeRaw) else {
            print("Error: Unknown project type '\(typeRaw)'")
            print("Available types: swift-package, macos-app, typescript-extension, automation-extension, source-control-extension")
            return 1
        }

        let name = (args.count > 1 && !args[1].hasPrefix("-")) ? args[1] : "My\(type.displayName.replacingOccurrences(of: " ", with: ""))"
        var outDir = FileManager.default.currentDirectoryPath

        if let outIdx = args.firstIndex(of: "--out"), outIdx + 1 < args.count {
            outDir = args[outIdx + 1]
        } else if args.count > 1 && !args[1].hasPrefix("-") {
            outDir = (outDir as NSString).appendingPathComponent(name)
        }

        let identifier = "com.swiftcode.\(name.lowercased())"
        let options = ProjectGeneratorOptions(
            type: type,
            name: name,
            identifier: identifier,
            destinationDirectory: outDir
        )

        print("Initializing \(type.displayName) '\(name)' at \(outDir)...")
        let metadata = try coordinator.projectGenerator.generate(options: options)
        print("✅ Project created successfully!")
        print("ID: \(metadata.id)")
        print("Type: \(metadata.type.rawValue)")
        print("Targets: \(metadata.targets.map { $0.name }.joined(separator: ", "))")
        return 0
    }

    static func runValidate(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        let path = args.first ?? FileManager.default.currentDirectoryPath
        print("Validating '\(path)'...")

        let diags = coordinator.extensionValidator.validateFile(at: path)
        if diags.isEmpty {
            print("✅ Validation passed: No issues found.")
            return 0
        } else {
            print(DiagnosticFormatter.formatText(diags))
            let hasErrors = diags.contains { $0.severity == .error }
            return hasErrors ? 1 : 0
        }
    }

    static func runBuild(coordinator: SwiftCodeSDKCoordinator, args: [String]) async throws -> Int32 {
        let path = args.first(where: { !$0.hasPrefix("-") }) ?? FileManager.default.currentDirectoryPath
        let isDebug = args.contains("--debug")
        let config = BuildConfig(
            projectPath: path,
            configuration: isDebug ? .debug : .release
        )

        print("Building project at '\(path)' [\(isDebug ? "Debug" : "Release")]...")
        let result = try await coordinator.buildService.build(config: config)

        if !result.stdout.isEmpty {
            print(result.stdout)
        }
        if !result.stderr.isEmpty {
            fputs(result.stderr + "\n", stderr)
        }

        if !result.diagnostics.isEmpty {
            print("\nBuild Diagnostics:")
            print(DiagnosticFormatter.formatText(result.diagnostics))
        }

        if result.succeeded {
            print("✅ Build succeeded in \(String(format: "%.2f", result.duration))s")
            return 0
        } else {
            print("❌ Build failed with exit code \(result.exitCode)")
            return result.exitCode != 0 ? result.exitCode : 1
        }
    }

    static func runTest(coordinator: SwiftCodeSDKCoordinator, args: [String]) async throws -> Int32 {
        let path = args.first(where: { !$0.hasPrefix("-") }) ?? FileManager.default.currentDirectoryPath
        print("Running tests in '\(path)'...")

        let config = BuildConfig(
            projectPath: path,
            configuration: .debug,
            additionalArguments: ["test", "--disable-sandbox"]
        )

        let result = try await coordinator.buildService.build(config: config)
        if !result.stdout.isEmpty {
            print(result.stdout)
        }
        if !result.stderr.isEmpty {
            fputs(result.stderr + "\n", stderr)
        }

        if result.succeeded {
            print("✅ Tests passed.")
            return 0
        } else {
            print("❌ Tests failed with exit code \(result.exitCode)")
            return result.exitCode != 0 ? result.exitCode : 1
        }
    }

    static func runInspect(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        let path = args.first ?? FileManager.default.currentDirectoryPath
        let metadata = try coordinator.projectInspector.inspect(at: path)

        print("=== Project Metadata ===")
        print("Name:           \(metadata.name)")
        print("ID:             \(metadata.id)")
        print("Type:           \(metadata.type.displayName)")
        print("Version:        \(metadata.version)")
        print("Root Path:      \(metadata.rootPath)")
        print("Configurations: \(metadata.configurations.joined(separator: ", "))")
        print("Targets:")
        for t in metadata.targets {
            print("  - \(t.name) (\(t.type))")
        }
        return 0
    }

    static func runPackage(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        let path = args.first(where: { !$0.hasPrefix("-") }) ?? FileManager.default.currentDirectoryPath
        var outDir = (path as NSString).appendingPathComponent("dist")
        if let outIdx = args.firstIndex(of: "--out"), outIdx + 1 < args.count {
            outDir = args[outIdx + 1]
        }

        print("Packaging extension at '\(path)' to '\(outDir)'...")
        let info = try coordinator.extensionPackager.package(extensionDirectory: path, outputDirectory: outDir)
        print("✅ Package created successfully!")
        print("Archive: \(info.packagePath)")
        print("Size:    \(info.archiveSize) bytes")
        print("SHA-256: \(info.sha256)")
        return 0
    }

    static func runVerify(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        guard let path = args.first else {
            print("Error: Missing package archive path to verify.")
            return 1
        }

        print("Verifying package at '\(path)'...")
        let (isValid, diags) = try coordinator.extensionPackager.verify(packagePath: path)

        if !diags.isEmpty {
            print(DiagnosticFormatter.formatText(diags))
        }

        if isValid {
            print("✅ Package verified: Integrity check passed.")
            return 0
        } else {
            print("❌ Package verification failed.")
            return 1
        }
    }

    static func runDocs(coordinator: SwiftCodeSDKCoordinator, args: [String]) throws -> Int32 {
        print("=== SwiftCode SDK Documentation ===")
        print("Version: \(SDKVersion.current)")
        print("Offline Documentation Directory: \(coordinator.configuration.documentationDirectory)")
        print("\nAvailable Guides & Topics:")
        print("  1. Getting Started:       documentation/guides/getting-started.md")
        print("  2. Architecture:          documentation/guides/architecture.md")
        print("  3. Extension Manifest:    documentation/guides/extension-manifest.md")
        print("  4. Capabilities & Security: documentation/guides/capabilities-security.md")
        print("  5. CLI Command Reference: documentation/guides/cli-reference.md")
        print("  6. API Reference:         documentation/api/index.md")
        print("  7. Troubleshooting:       documentation/guides/troubleshooting.md")
        print("\nTo view offline documentation, inspect the documentation/ directory or run offline-index.")
        return 0
    }
}
