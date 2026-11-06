import Foundation
import SwiftCodeExtensions
import SwiftCodeSDK

// MARK: - First-launch choice
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKFirstLaunchInstallerView.swift`
// (`SDKStudioFirstLaunchChoice`). Records whether the user installed,
// declined, or asked to be reminded later; `shouldPrompt` is true only
// while nothing is recorded and the SDK is not already installed. The
// install check itself is the Host slice's `SDKInstaller.inspect()` —
// this type takes the installed flag as a parameter so Studio stays
// testable without the installer.

public enum SDKStudioFirstLaunchChoice {
    private static let choiceKey = "com.swiftcode.sdk.studio.firstLaunchChoice"
    private static let installedValue = "installed"
    private static let declinedValue = "declined"
    private static let remindLaterValue = "remindLater"

    public enum Choice: String {
        case installed
        case declined
        case remindLater
    }

    public static func recordedChoice(defaults: UserDefaults = .standard) -> Choice? {
        guard let raw = defaults.string(forKey: choiceKey) else { return nil }
        return Choice(rawValue: raw)
    }

    public static func shouldPrompt(sdkInstalled: Bool, defaults: UserDefaults = .standard) -> Bool {
        if sdkInstalled { return false }
        return recordedChoice(defaults: defaults) == nil
    }

    public static func recordInstalled(defaults: UserDefaults = .standard) {
        defaults.set(installedValue, forKey: choiceKey)
    }

    public static func recordDeclined(defaults: UserDefaults = .standard) {
        defaults.set(declinedValue, forKey: choiceKey)
    }

    public static func recordRemindLater(defaults: UserDefaults = .standard) {
        defaults.set(remindLaterValue, forKey: choiceKey)
    }
}

// MARK: - Installer seam
//
// Legacy: `SwiftCode/SDK/Host/SDKInstaller.swift` (Host slice). Studio
// needs only: installed?, install with live log lines, and the default
// prefix. `SDKStudioInstallerHost` below adapts the real Host installer;
// `SDKStudioInstallerUnavailable` remains as the honest placeholder for
// tests and for builds without the installer.

public enum SDKStudioInstallerStatus: Equatable, Sendable {
    case ok(version: String)
    case notInstalled
    case versionMismatch(found: String, expected: String)
    case error(String)
}

public struct SDKStudioInstallResult: Equatable, Sendable {
    public let succeeded: Bool
    public let detail: String
    public let logLines: [String]

    public init(succeeded: Bool, detail: String, logLines: [String] = []) {
        self.succeeded = succeeded
        self.detail = detail
        self.logLines = logLines
    }
}

public protocol SDKStudioInstaller: Sendable {
    static var expectedVersion: String { get }
    static var defaultPrefix: URL { get }
    func inspect() -> SDKStudioInstallerStatus
    func install(progress: @escaping @Sendable (String) -> Void) async -> SDKStudioInstallResult
    func bundledFallbackURL() -> URL?
}

/// The placeholder the Studio UI used before the Host slice landed the
/// real installer: every operation honestly reports "not available".
/// Kept for tests; the Studio views now use `SDKStudioInstallerHost`.
public struct SDKStudioInstallerUnavailable: SDKStudioInstaller {
    public static let expectedVersion: String = SDKVersion.current.description
    public static let defaultPrefix: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".swiftcode/sdk")
    }()

    public init() {}
    public func inspect() -> SDKStudioInstallerStatus { .notInstalled }
    public func install(progress: @escaping @Sendable (String) -> Void) async -> SDKStudioInstallResult {
        SDKStudioInstallResult(succeeded: false, detail: "The SDK installer has not been ported yet (Host slice).")
    }
    public func bundledFallbackURL() -> URL? { nil }
}

/// The live installer adapter (Wave 14 coordinator): delegates to the
/// Host slice's real `SDKInstaller` (idempotent npm install of
/// `@swiftcode/sdk`, pinned GitHub release with bundled fallback).
/// No bundled tarball ships in-repo, so `bundledFallbackURL()` is nil
/// and the installer honestly reports the fallback as unavailable when
/// the remote download fails.
public struct SDKStudioInstallerHost: SDKStudioInstaller {
    public static let expectedVersion: String = SDKInstaller.expectedVersion
    public static let defaultPrefix: URL = SDKInstaller.defaultPrefix

    public init() {}

    public func inspect() -> SDKStudioInstallerStatus {
        switch SDKInstaller.inspect() {
        case .ok(let version):
            return .ok(version: version)
        case .missing:
            return .notInstalled
        case .versionMismatch(let actual):
            return .versionMismatch(found: actual, expected: SDKInstaller.expectedVersion)
        case .corrupt(let reason):
            return .error(reason)
        }
    }

    public func install(progress: @escaping @Sendable (String) -> Void) async -> SDKStudioInstallResult {
        let result = await SDKInstaller.install(options: SDKInstaller.InstallOptions()) { line in
            progress(line.text)
        }
        return SDKStudioInstallResult(succeeded: result.success, detail: result.message, logLines: result.log)
    }

    public func bundledFallbackURL() -> URL? { nil }
}

// MARK: - Project wizard and scaffold
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKStudioProjectsView.swift`
// (`WizardConfig`, `WizardField`, `Validators`, `ScaffoldEngine`).
// Three wizards, field-for-field: New Extension (id, name, version,
// description, outDir, sdkPackage), New TypeScript Project (name, slug,
// version, description, outDir), New Swift Project (name, bundleId,
// outDir). Validation mirrors the rules in
// `SwiftCode/SDK/TypeScript/cli/create-extension.mjs`. The scaffold
// writer refuses a non-empty target and refuses any template path that
// escapes the target (containment anchor, verbatim rule).

public enum SDKStudioWizardKind: String, Sendable, CaseIterable {
    case newExtension
    case newTypeScriptProject
    case newSwiftProject
}

public struct SDKStudioWizardField: Identifiable, Sendable {
    public enum Kind: Sendable {
        case text(lines: Int)
        case directory
    }

    public let key: String
    public let label: String
    public let placeholder: String
    public let kind: Kind
    public let help: String
    public let initialValue: String
    public let validate: @Sendable (String) -> String?

    public var id: String { key }

    public init(key: String, label: String, placeholder: String, kind: Kind, help: String,
                initialValue: String, validate: @escaping @Sendable (String) -> String?) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.kind = kind
        self.help = help
        self.initialValue = initialValue
        self.validate = validate
    }
}

public struct SDKStudioWizardConfig: Sendable {
    public let kind: SDKStudioWizardKind
    public let title: String
    public let subtitle: String
    public let bannerTitle: String
    public let bannerBody: String
    public let fields: [SDKStudioWizardField]

    public static var newExtension: SDKStudioWizardConfig {
        SDKStudioWizardConfig(
            kind: .newExtension,
            title: "New Extension",
            subtitle: "TypeScript extension with a swiftcode.json manifest. Extensions run out-of-process under host capability controls.",
            bannerTitle: "Capabilities & Visual Manifest Editor",
            bannerBody: "The starter scaffold declares source-control.read and build.execute. After creation, click “Edit Manifest” to toggle any of the 35 canonical SDK capabilities, edit contributed commands, or configure Assist access in the visual Manifest Editor.",
            fields: [
                SDKStudioWizardField(key: "id", label: "Extension ID", placeholder: "com.example.my-ext",
                                     kind: .text(lines: 1),
                                     help: "Reverse-DNS identifier. Also used as the install directory name.",
                                     initialValue: "", validate: SDKStudioWizardValidators.extensionID),
                SDKStudioWizardField(key: "name", label: "Display Name", placeholder: "My Extension",
                                     kind: .text(lines: 1),
                                     help: "Human-readable name, shown in the manifest and README.",
                                     initialValue: "", validate: SDKStudioWizardValidators.displayName),
                SDKStudioWizardField(key: "version", label: "Version", placeholder: "0.1.0",
                                     kind: .text(lines: 1),
                                     help: "Semantic version of the extension package.",
                                     initialValue: "0.1.0", validate: SDKStudioWizardValidators.semver),
                SDKStudioWizardField(key: "description", label: "Description", placeholder: "What this extension does…",
                                     kind: .text(lines: 3),
                                     help: "Optional. Plain-language description, up to 1000 characters.",
                                     initialValue: "", validate: SDKStudioWizardValidators.description),
                SDKStudioWizardField(key: "outDir", label: "Project Directory", placeholder: "No directory chosen",
                                     kind: .directory,
                                     help: "The extension project is created inside this directory. It must be empty or not exist yet.",
                                     initialValue: "", validate: SDKStudioWizardValidators.targetDirectory),
                SDKStudioWizardField(key: "sdkPackage", label: "SDK Package (@swiftcode/sdk)",
                                     placeholder: "No SDK package located", kind: .directory,
                                     help: "Local @swiftcode/sdk package directory. The generated package.json depends on it via a file: URL. Auto-detected from the app bundle or SWIFTCODE_SDK_PACKAGE; override with Browse if needed.",
                                     initialValue: SDKStudioScaffold.defaultSDKPackageDir() ?? "",
                                     validate: SDKStudioWizardValidators.sdkPackage),
            ])
    }

    public static var newTypeScriptProject: SDKStudioWizardConfig {
        SDKStudioWizardConfig(
            kind: .newTypeScriptProject,
            title: "New TypeScript Project",
            subtitle: "Standalone TypeScript project with the verified npm / tsc / node workflow. User-owned code — not subject to extension sandbox restrictions.",
            bannerTitle: "Standalone, not an extension",
            bannerBody: "This scaffold produces ordinary user-owned code: no swiftcode.json manifest, no capability declarations, no runtime sandbox. It builds and runs with the language's own toolchain.",
            fields: [
                SDKStudioWizardField(key: "name", label: "Project Name", placeholder: "My Project",
                                     kind: .text(lines: 1),
                                     help: "Human-readable name, shown in the README and source header.",
                                     initialValue: "", validate: SDKStudioWizardValidators.displayName),
                SDKStudioWizardField(key: "slug", label: "Package Name", placeholder: "my-project",
                                     kind: .text(lines: 1),
                                     help: "npm package name: lowercase letters, digits, dots, hyphens, underscores, tildes.",
                                     initialValue: "", validate: SDKStudioWizardValidators.npmSlug),
                SDKStudioWizardField(key: "version", label: "Version", placeholder: "0.1.0",
                                     kind: .text(lines: 1),
                                     help: "Semantic version of the package.",
                                     initialValue: "0.1.0", validate: SDKStudioWizardValidators.semver),
                SDKStudioWizardField(key: "description", label: "Description", placeholder: "What this project does…",
                                     kind: .text(lines: 3),
                                     help: "Optional. Plain-language description, up to 1000 characters.",
                                     initialValue: "", validate: SDKStudioWizardValidators.description),
                SDKStudioWizardField(key: "outDir", label: "Project Directory", placeholder: "No directory chosen",
                                     kind: .directory,
                                     help: "The project is created inside this directory. It must be empty or not exist yet.",
                                     initialValue: "", validate: SDKStudioWizardValidators.targetDirectory),
            ])
    }

    public static var newSwiftProject: SDKStudioWizardConfig {
        SDKStudioWizardConfig(
            kind: .newSwiftProject,
            title: "New Swift Project",
            subtitle: "Standalone SwiftUI macOS app scaffold. User-owned code with the ordinary Swift and Xcode workflow.",
            bannerTitle: "Scaffold contents",
            bannerBody: "Generates the Standalone-Swift template: App.swift (the @main entry point), ContentView.swift, a README with the Xcode setup steps, and a .gitignore. App identity (bundle ID, signing) is set on your own Xcode target, not in these files.",
            fields: [
                SDKStudioWizardField(key: "name", label: "App Name", placeholder: "MyApp",
                                     kind: .text(lines: 1),
                                     help: "Used as the Swift type name (e.g. MyApp becomes MyAppApp and MyApp.swift). Letters, digits, underscores; must start with a letter or underscore.",
                                     initialValue: "", validate: SDKStudioWizardValidators.swiftTypeName),
                SDKStudioWizardField(key: "bundleId", label: "Bundle Identifier", placeholder: "com.example.myapp",
                                     kind: .text(lines: 1),
                                     help: "Reverse-DNS bundle identifier recorded in the README.",
                                     initialValue: "", validate: SDKStudioWizardValidators.bundleID),
                SDKStudioWizardField(key: "outDir", label: "Project Directory", placeholder: "No directory chosen",
                                     kind: .directory,
                                     help: "The project is created inside this directory. It must be empty or not exist yet.",
                                     initialValue: "", validate: SDKStudioWizardValidators.targetDirectory),
            ])
    }
}

public enum SDKStudioWizardValidators {
    public static func extensionID(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.count > 128 { return "Must be at most 128 characters." }
        if v.wholeMatch(of: #/^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9-]*)+$/#) == nil {
            return "Must be reverse-DNS: letters, digits, hyphens, at least one dot (e.g. com.example.my-ext)."
        }
        return nil
    }

    public static func bundleID(_ value: String) -> String? { extensionID(value) }

    public static func displayName(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.count > 128 { return "Must be at most 128 characters." }
        return nil
    }

    public static func semver(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.wholeMatch(of: #/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-((0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$/#) == nil {
            return "Must be valid semantic versioning (e.g. 0.1.0)."
        }
        return nil
    }

    public static func description(_ value: String) -> String? {
        if value.count > 1000 { return "Must be at most 1000 characters." }
        return nil
    }

    public static func npmSlug(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.wholeMatch(of: #/^[a-z0-9][a-z0-9._~-]*$/#) == nil {
            return "Must be a lowercase npm package name."
        }
        return nil
    }

    public static func swiftTypeName(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required." }
        if v.wholeMatch(of: #/^[A-Za-z_][A-Za-z0-9_]*$/#) == nil {
            return "Must be a valid Swift type name."
        }
        return nil
    }

    public static func targetDirectory(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return "Required — choose a directory." }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: v, isDirectory: &isDir) {
            if !isDir.boolValue { return "Must be a directory." }
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: v)) ?? []
            if !entries.isEmpty { return "Directory must be empty." }
        }
        return nil
    }

    public static func sdkPackage(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { return nil }
        let packageJSON = (v as NSString).appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: packageJSON)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String, name == "@swiftcode/sdk" else {
            return "Not a valid @swiftcode/sdk package directory."
        }
        return nil
    }
}

public enum SDKStudioScaffoldError: Error, Sendable {
    case targetNotEmpty(path: String)
    case invalidSDKPackage(path: String, reason: String)
    case writeFailed(path: String, underlying: Error)
    case missingValue(key: String)
}

public enum SDKStudioScaffold {
    /// Auto-detects the local `@swiftcode/sdk` package directory: the
    /// `SWIFTCODE_SDK_PACKAGE` environment variable, then the app bundle's
    /// `SwiftCodeSDK` resources, then the installed SDK prefix.
    public static func defaultSDKPackageDir() -> String? {
        if let env = ProcessInfo.processInfo.environment["SWIFTCODE_SDK_PACKAGE"], !env.isEmpty { return env }
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/node_modules/@swiftcode/sdk").path,
           FileManager.default.fileExists(atPath: bundled) { return bundled }
        let installed = SDKStudioInstallerHost.defaultPrefix
            .appendingPathComponent("node_modules/@swiftcode/sdk").path
        if FileManager.default.fileExists(atPath: installed) { return installed }
        return nil
    }

    /// Creates a project from `config` + `values` at
    /// `values["outDir"]`, writing the scaffold files. Returns the
    /// target directory and the written relative paths.
    public static func create(config: SDKStudioWizardConfig, values: [String: String],
                             progress: (String) -> Void = { _ in }) throws -> (target: URL, written: [String]) {
        guard let outDir = values["outDir"], !outDir.isEmpty else {
            throw SDKStudioScaffoldError.missingValue(key: "outDir")
        }
        let target = URL(fileURLWithPath: outDir).standardizedFileURL
        let files = templateFiles(config: config, values: values)
        let written = try writeFiles(files, to: target, progress: progress)
        return (target, written)
    }

    private struct TemplateFile {
        let path: String
        let content: String
    }

    private static func templateFiles(config: SDKStudioWizardConfig, values: [String: String]) -> [TemplateFile] {
        switch config.kind {
        case .newExtension:
            let id = values["id"] ?? ""
            let name = values["name"] ?? ""
            let version = values["version"] ?? "0.1.0"
            let desc = values["description"] ?? ""
            let sdkPackage = values["sdkPackage"] ?? ""
            let sdkDep = sdkPackage.isEmpty ? "\"@swiftcode/sdk\": \"^1.0.0\"" : "\"@swiftcode/sdk\": \"file:\(sdkPackage)\""
            let manifest = """
            {
              "manifestVersion": 1,
              "id": "\(id)",
              "name": "\(name)",
              "version": "\(version)",
              "description": "\(desc)",
              "type": "extension",
              "runtime": { "language": "typescript", "entrypoint": "dist/index.js", "minimumSwiftCodeVersion": "1.0.0" },
              "sdk": { "name": "@swiftcode/sdk", "versionRange": "^1.0.0", "protocolVersion": 1 },
              "capabilities": [
                { "id": "source-control.read", "reason": "Read repository state for the extension's commands." },
                { "id": "build.execute", "reason": "Run builds for the extension's commands." }
              ],
              "contributes": { "commands": [{ "id": "hello", "title": "Hello" }] },
              "assist": { "requested": false }
            }
            """
            return [
                TemplateFile(path: "swiftcode.json", content: manifest),
                TemplateFile(path: "package.json", content: """
                {
                  "name": "\(id)",
                  "version": "\(version)",
                  "description": "\(desc)",
                  "main": "dist/index.js",
                  "scripts": { "build": "tsc -p tsconfig.json" },
                  "dependencies": { \(sdkDep) },
                  "devDependencies": { "typescript": "^5.0.0" }
                }
                """),
                TemplateFile(path: "tsconfig.json", content: """
                {
                  "compilerOptions": { "target": "ES2022", "module": "commonjs", "outDir": "dist", "strict": true },
                  "include": ["src"]
                }
                """),
                TemplateFile(path: "src/index.ts", content: """
                import { sdk } from "@swiftcode/sdk";

                // \(name) — starter extension.
                sdk.commands.register("hello", async () => {
                  await sdk.workspace.showMessage("Hello from \(name)!");
                });
                """),
                TemplateFile(path: "README.md", content: "# \(name)\n\n\(desc)\n\nExtension ID: `\(id)`\n"),
            ]
        case .newTypeScriptProject:
            let name = values["name"] ?? ""
            let slug = values["slug"] ?? ""
            let version = values["version"] ?? "0.1.0"
            let desc = values["description"] ?? ""
            return [
                TemplateFile(path: "package.json", content: """
                {
                  "name": "\(slug)",
                  "version": "\(version)",
                  "description": "\(desc)",
                  "main": "dist/index.js",
                  "scripts": { "build": "tsc -p tsconfig.json", "start": "node dist/index.js" },
                  "devDependencies": { "typescript": "^5.0.0" }
                }
                """),
                TemplateFile(path: "tsconfig.json", content: """
                {
                  "compilerOptions": { "target": "ES2022", "module": "commonjs", "outDir": "dist", "strict": true },
                  "include": ["src"]
                }
                """),
                TemplateFile(path: "src/index.ts", content: """
                // \(name) — standalone TypeScript project.
                console.log("Hello from \(name)!");
                """),
                TemplateFile(path: "README.md", content: "# \(name)\n\n\(desc)\n"),
            ]
        case .newSwiftProject:
            let name = values["name"] ?? ""
            let bundleId = values["bundleId"] ?? ""
            return [
                TemplateFile(path: "App.swift", content: """
                import SwiftUI

                @main
                struct \(name)App: App {
                    var body: some Scene {
                        WindowGroup {
                            ContentView()
                        }
                    }
                }
                """),
                TemplateFile(path: "ContentView.swift", content: """
                import SwiftUI

                struct ContentView: View {
                    var body: some View {
                        Text("Hello, \(name)!")
                    }
                }
                """),
                TemplateFile(path: "README.md", content: """
                # \(name)

                Bundle identifier: `\(bundleId)`

                Open this folder in Xcode as a SwiftUI app project, or create a new
                Xcode project with bundle identifier `\(bundleId)` and add these files.
                """),
                TemplateFile(path: ".gitignore", content: ".DS_Store\n"),
            ]
        }
    }

    private static func writeFiles(_ files: [TemplateFile], to target: URL,
                                   progress: (String) -> Void) throws -> [String] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: target.path, isDirectory: &isDir) {
            guard isDir.boolValue else { throw SDKStudioScaffoldError.targetNotEmpty(path: target.path) }
            let entries = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
            if !entries.isEmpty { throw SDKStudioScaffoldError.targetNotEmpty(path: target.path) }
        }
        var written: [String] = []
        let targetPath = target.standardizedFileURL.path
        for file in files {
            let url = target.appendingPathComponent(file.path)
            let resolvedPath = url.standardizedFileURL.path
            guard resolvedPath == targetPath || resolvedPath.hasPrefix(targetPath + "/") else {
                throw SDKStudioScaffoldError.writeFailed(
                    path: file.path,
                    underlying: NSError(domain: "SDKStudio.Scaffold", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "A template path escapes the target directory."]))
            }
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try file.content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw SDKStudioScaffoldError.writeFailed(path: file.path, underlying: error)
            }
            written.append(file.path)
            progress(file.path)
        }
        return written
    }
}

// MARK: - Recent projects
//
// Legacy: `SDKStudioProjectsView` (`com.swiftcode.sdk.studio.recentProjects`).

public enum SDKStudioRecentProjects {
    private static let key = "com.swiftcode.sdk.studio.recentProjects"
    public static let maxEntries = 20

    public static func load(defaults: UserDefaults = .standard) -> [String] {
        let list = defaults.stringArray(forKey: key) ?? []
        return list.filter { FileManager.default.fileExists(atPath: $0) }
    }

    public static func record(_ url: URL, defaults: UserDefaults = .standard) {
        var list = defaults.stringArray(forKey: key) ?? []
        let path = url.standardizedFileURL.path
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        if list.count > maxEntries { list = Array(list.prefix(maxEntries)) }
        defaults.set(list, forKey: key)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Grant store seam
//
// Legacy: `SwiftCode/SDK/Host/CapabilityBroker/Grants/SDKGrantStore.swift`
// (`SDKGrantRecord` with package digest, scope, granted-by, expiry, and a
// never-cleared revoked tombstone). SwiftCode's `PermissionManager`
// (`SwiftCodeExtensions/Capabilities.swift`) is the Host slice's live grant
// store: `grants.json`, deny-by-default, revoke effective on next call —
// but it keeps no tombstones, no package digests, and no extension display
// names. The Studio grant manager therefore talks to this protocol; the
// adapter below synthesizes records from live grants (revoked records are
// absent — the tombstone gap is reported to the coordinator, not faked).

public struct SDKStudioGrantRecord: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let extensionID: String
    public let packageDigest: String
    public let packageVersion: String
    public let capability: SDKCapabilityID
    public let scopeDescription: String
    public let grantedAt: Date
    public let grantedBy: String
    public let expiresAt: Date?
    public let revokedAt: Date?
    public let policyVersion: Int

    public init(id: UUID = UUID(), extensionID: String, packageDigest: String, packageVersion: String,
                capability: SDKCapabilityID, scopeDescription: String, grantedAt: Date = Date(),
                grantedBy: String, expiresAt: Date? = nil, revokedAt: Date? = nil, policyVersion: Int = 1) {
        self.id = id
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.packageVersion = packageVersion
        self.capability = capability
        self.scopeDescription = scopeDescription
        self.grantedAt = grantedAt
        self.grantedBy = grantedBy
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.policyVersion = policyVersion
    }

    public func isActive(now: Date = Date()) -> Bool {
        if revokedAt != nil { return false }
        if let expiresAt, now >= expiresAt { return false }
        return true
    }

    public func revoked() -> SDKStudioGrantRecord {
        SDKStudioGrantRecord(id: id, extensionID: extensionID, packageDigest: packageDigest,
                             packageVersion: packageVersion, capability: capability,
                             scopeDescription: scopeDescription, grantedAt: grantedAt, grantedBy: grantedBy,
                             expiresAt: expiresAt, revokedAt: Date(), policyVersion: policyVersion)
    }
}

public protocol SDKStudioGrantStore: Sendable {
    func grants(for extensionID: String) async throws -> [SDKStudioGrantRecord]
    func extensionName(for extensionID: String) async -> String?
    func revoke(_ record: SDKStudioGrantRecord) async throws
    func revokeAll(for extensionID: String) async throws
}

/// Live-grant adapter over `PermissionManager`: records are synthesized
/// from currently-granted capabilities (mapped from the v2 runtime
/// capabilities back to the SDK ids they enforce), merged with the
/// revoked tombstones kept in the Host slice's `SDKGrantStore` (S-2).
/// Revocation is real and immediate in the live store; the tombstone is
/// stamped in the record store best-effort (a tombstone failure never
/// fails the revoke itself — the grant is already gone).
public struct SDKPermissionManagerGrantStore: SDKStudioGrantStore {
    private let permissions: PermissionManager
    private let grantRecords: SDKGrantStore

    public init(permissions: PermissionManager, grantRecords: SDKGrantStore = .shared) {
        self.permissions = permissions
        self.grantRecords = grantRecords
    }

    public func grants(for extensionID: String) async throws -> [SDKStudioGrantRecord] {
        let granted = permissions.grantedCapabilities(for: extensionID)
        var records = granted.flatMap { v2 -> [SDKStudioGrantRecord] in
            SDKCapabilityID.allCases
                .filter { ExtensionCapability.v2Capabilities(for: $0).contains(v2) }
                .map { sdk in
                    SDKStudioGrantRecord(extensionID: extensionID, packageDigest: "", packageVersion: "",
                                         capability: sdk, scopeDescription: v2.displayName,
                                         grantedBy: "user-approval")
                }
        }
        // Revoked history from the durable record store (tombstones are
        // kept forever; a re-granted capability appears twice — once
        // live, once revoked — which is the audit trail).
        let stored = await grantRecords.grants(for: extensionID)
        for tombstone in stored where tombstone.revokedAt != nil {
            records.append(SDKStudioGrantRecord(
                id: tombstone.id, extensionID: tombstone.extensionID,
                packageDigest: tombstone.packageDigest, packageVersion: tombstone.packageVersion,
                capability: tombstone.capability,
                scopeDescription: tombstone.scope.projectRootPath.isEmpty
                    ? "All projects (flat grant)" : "Project: \(tombstone.scope.projectRootPath)",
                grantedAt: tombstone.grantedAt, grantedBy: tombstone.grantedBy,
                expiresAt: tombstone.expiresAt, revokedAt: tombstone.revokedAt,
                policyVersion: tombstone.policyVersion))
        }
        return records.sorted { $0.grantedAt < $1.grantedAt }
    }

    public func extensionName(for extensionID: String) async -> String? {
        await SDKExtensionRegistry.shared.installedExtension(id: extensionID)?.name
    }

    public func revoke(_ record: SDKStudioGrantRecord) async throws {
        for v2 in ExtensionCapability.v2Capabilities(for: record.capability) {
            permissions.revoke(extensionId: record.extensionID, capability: v2)
        }
        await stampTombstone(extensionID: record.extensionID, capability: record.capability,
                             packageDigest: record.packageDigest, packageVersion: record.packageVersion)
    }

    public func revokeAll(for extensionID: String) async throws {
        // Capture the live grants first: only capabilities that were
        // actually held get a tombstone.
        let live = permissions.grantedCapabilities(for: extensionID)
        let liveSDKCapabilities = Set(SDKCapabilityID.allCases.filter { sdk in
            ExtensionCapability.v2Capabilities(for: sdk).contains(where: { live.contains($0) })
        })
        permissions.revokeAll(for: extensionID)
        // Stamp every record the store holds for this extension, plus a
        // tombstone for each live-only capability (no record yet).
        try? await grantRecords.revokeAll(for: extensionID)
        for sdk in liveSDKCapabilities {
            await stampTombstone(extensionID: extensionID, capability: sdk,
                                 packageDigest: "", packageVersion: "")
        }
    }

    /// Stamps a revocation tombstone for one capability: revokes any
    /// record the store already holds, and appends a tombstone record
    /// when the grant lived only in the flat store. Best-effort — the
    /// live revoke above already happened, so a record-store failure
    /// must not surface as a revoke failure.
    private func stampTombstone(extensionID: String, capability: SDKCapabilityID,
                                packageDigest: String, packageVersion: String) async {
        let installed = await SDKExtensionRegistry.shared.installedExtension(id: extensionID)
        let digest = installed?.packageDigest ?? packageDigest
        let version = installed?.version ?? packageVersion
        let stored = await grantRecords.grants(for: extensionID)
        if stored.contains(where: { $0.capability == capability }) {
            try? await grantRecords.revoke(extensionID: extensionID, capability: capability)
        } else {
            try? await grantRecords.recordRevocation(
                extensionID: extensionID, capability: capability,
                packageDigest: digest, packageVersion: version)
        }
    }
}

// MARK: - Developer API keys seam
//
// Legacy: `SwiftCode/SDK/Host/APIKeys/SDKAPIKey.swift` +
// `SDKAPIKeyStore.swift` (HMAC-SHA256 `sc_dev_live_` / `sc_dev_test_`
// secrets against a Keychain device key; metadata only is stored, the
// secret itself is never persisted; revocation is immediate; three v1
// scopes `apps:create`, `apps:publish`, `capabilities:request`).
// `SDKHostAPIKeyStore` below adapts the real Host store; Studio talks to
// this protocol so the API Keys view never invents its own key storage.

public struct SDKStudioAPIKeyScope: Sendable, Hashable, RawRepresentable, Codable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked rawValue: String) { self.rawValue = rawValue }

    public static let appsCreate = SDKStudioAPIKeyScope(unchecked: "apps:create")
    public static let appsPublish = SDKStudioAPIKeyScope(unchecked: "apps:publish")
    public static let capabilitiesRequest = SDKStudioAPIKeyScope(unchecked: "capabilities:request")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let scope = SDKStudioAPIKeyScope(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "API key scope must be a non-empty string.")
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SDKStudioAPIKey: Identifiable, Sendable, Codable {
    public let id: UUID
    public let keyPrefix: String
    public let label: String
    public let scopes: Set<SDKStudioAPIKeyScope>
    public let entitlements: Set<String>
    public let createdAt: Date
    public var lastUsedAt: Date?
    public var revokedAt: Date?
    public let expiresAt: Date?
    public let isLive: Bool

    public init(id: UUID = UUID(), keyPrefix: String, label: String, scopes: Set<SDKStudioAPIKeyScope>,
                entitlements: Set<String> = [], createdAt: Date = Date(), lastUsedAt: Date? = nil,
                revokedAt: Date? = nil, expiresAt: Date? = nil, isLive: Bool = true) {
        self.id = id
        self.keyPrefix = keyPrefix
        self.label = label
        self.scopes = scopes
        self.entitlements = entitlements
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.revokedAt = revokedAt
        self.expiresAt = expiresAt
        self.isLive = isLive
    }

    public var isRevoked: Bool { revokedAt != nil }
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

public enum SDKStudioAPIKeyStoreError: Error, Sendable {
    case unavailable(String)
    case invalid(String)
}

public protocol SDKStudioAPIKeyStore: Sendable {
    /// Creates a key and returns its metadata plus the secret, shown
    /// exactly once. The secret is never stored.
    func createKey(label: String, isLive: Bool, scopes: Set<SDKStudioAPIKeyScope>,
                   expiresAt: Date?) async throws -> (key: SDKStudioAPIKey, secret: String)
    func list() async throws -> [SDKStudioAPIKey]
    func revoke(id: UUID) async throws
}

/// The live key-store adapter (Wave 14 coordinator): delegates to the
/// Host slice's real `SDKAPIKeyStore` (HMAC-SHA256 secrets against a
/// Keychain device key; metadata only is persisted). Scope and
/// entitlement values cross the boundary by raw string — both sides
/// accept any non-empty string — and `isLive` is derived from the key
/// prefix (`sc_dev_live_` vs `sc_dev_test_`), which is the same
/// information the Host store records.
public struct SDKHostAPIKeyStore: SDKStudioAPIKeyStore {
    private let store: SDKAPIKeyStore

    public init(store: SDKAPIKeyStore = .shared) {
        self.store = store
    }

    public func createKey(label: String, isLive: Bool, scopes: Set<SDKStudioAPIKeyScope>,
                          expiresAt: Date?) async throws -> (key: SDKStudioAPIKey, secret: String) {
        let hostScopes = Set(scopes.map { SDKAPIKeyScope($0.rawValue) })
        let (hostKey, secret) = try await store.createKey(label: label, scopes: hostScopes, isLive: isLive, expiresAt: expiresAt)
        return (key: try Self.toStudio(hostKey), secret: secret)
    }

    public func list() async throws -> [SDKStudioAPIKey] {
        try await store.list().map(Self.toStudio)
    }

    public func revoke(id: UUID) async throws {
        await store.revoke(id: id)
    }

    private static func toStudio(_ key: SDKAPIKey) throws -> SDKStudioAPIKey {
        let scopes = try key.scopes.map { host -> SDKStudioAPIKeyScope in
            guard let scope = SDKStudioAPIKeyScope(rawValue: host.rawValue) else {
                throw SDKStudioAPIKeyStoreError.invalid("Stored key scope is empty.")
            }
            return scope
        }
        return SDKStudioAPIKey(
            id: key.id,
            keyPrefix: key.keyPrefix,
            label: key.label,
            scopes: Set(scopes),
            entitlements: Set(key.entitlements.map(\.rawValue)),
            createdAt: key.createdAt,
            lastUsedAt: key.lastUsedAt,
            revokedAt: key.revokedAt,
            expiresAt: key.expiresAt,
            isLive: key.keyPrefix == SDKAPIKeyCodec.livePrefix
        )
    }
}

// MARK: - Security values seam
//
// Legacy: `SDKSecurityManagerView` lists per-app `use.Security` values
// (add / delete / delete-all) backed by the host security store. SwiftCode
// has no `use.Security` store yet (the Host slice owns it); Studio
// talks to this protocol and shows an honest unavailable state until
// the Host slice provides an implementation.

public struct SDKStudioSecurityApp: Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let valueIDs: [String]

    public init(id: String, displayName: String, valueIDs: [String]) {
        self.id = id
        self.displayName = displayName
        self.valueIDs = valueIDs
    }
}

public protocol SDKStudioSecurityStore: Sendable {
    func listApps() async throws -> [SDKStudioSecurityApp]
    func store(value: String, valueID: String, label: String?, promptText: String?, forApp appID: String) async throws
    func deleteValue(valueID: String, forApp appID: String) async throws
    func deleteAllValues(forApp appID: String) async throws
}

/// The live security-store adapter (S-4): delegates to the Host slice's
/// real `SDKSecurityService` (§5 of the SDK spec). `listApps` uses the
/// host's `listAllApps` enumeration (metadata only — values are never
/// returned). `store` is the HOST-side entry: the Studio user typed the
/// secret into the sheet, so it goes straight to `KeychainSDK.addValue`
/// (the extension-facing `addValue` collects through the host secure
/// prompt instead and never receives plaintext); `promptText` is unused
/// here because the value was already collected. `appID` is the
/// namespaced Security ID (`<extensionID>.<appSecurityID>`).
public struct SDKHostSecurityStore: SDKStudioSecurityStore {
    public init() {}

    public func listApps() async throws -> [SDKStudioSecurityApp] {
        let apps = try await SDKSecurityService.shared.listAllApps()
        var result: [SDKStudioSecurityApp] = []
        for app in apps {
            let name: String?
            if let extensionID = app.extensionID {
                name = await SDKExtensionRegistry.shared.installedExtension(id: extensionID)?.name
            } else {
                name = nil
            }
            result.append(SDKStudioSecurityApp(
                id: app.securityID,
                displayName: name ?? app.securityID,
                valueIDs: app.values.map(\.valueID)))
        }
        return result
    }

    public func store(value: String, valueID: String, label: String?, promptText: String?, forApp appID: String) async throws {
        _ = promptText
        _ = try KeychainSDK.addValue(securityID: appID, valueID: valueID, value: Data(value.utf8), label: label)
    }

    public func deleteValue(valueID: String, forApp appID: String) async throws {
        try KeychainSDK.deleteValue(securityID: appID, valueID: valueID)
    }

    public func deleteAllValues(forApp appID: String) async throws {
        _ = try KeychainSDK.deleteAllValues(securityID: appID)
    }
}

// MARK: - Assist access application seam
//
// Legacy: `AssistAccessFormView` submits an Assist access application
// (`SDKAssistApplication`, Host slice) for an extension + developer key:
// variant, own-UI, third-party models, data-leaves-device, contact. The
// form model below carries the validated application; `submit` (S-5)
// sends it to the Host slice's `SDKAssistApplicationStore` — the API key
// secret is passed in-memory only and never stored on this model — and
// approval stays a separate host action. Studio never approves
// applications itself.

public struct SDKStudioAssistAccessApplication: Sendable, Codable {
    public enum Variant: String, Sendable, Codable {
        case newApplication = "New Application"
        case existingApplication = "Existing Application"
    }

    public let extensionID: String
    public let displayName: String
    public let keyID: String?
    public let variant: Variant
    /// The SDK variant the application is for (Host `SDKAssistSDKVariant`).
    /// Defaults to the UI variant, matching Legacy's form default.
    public let sdkVariant: SDKAssistSDKVariant
    public let usageDescription: String
    public let hasOwnUI: Bool
    public let ownUIDescription: String?
    public let usesThirdPartyModels: Bool
    public let thirdPartyModels: String?
    public let dataLeavesDevice: Bool
    public let dataDestination: String?
    public let contactEmail: String

    public init(extensionID: String, displayName: String, keyID: String?, variant: Variant,
                sdkVariant: SDKAssistSDKVariant = .assistSDKUI,
                usageDescription: String, hasOwnUI: Bool, ownUIDescription: String?,
                usesThirdPartyModels: Bool, thirdPartyModels: String?,
                dataLeavesDevice: Bool, dataDestination: String?, contactEmail: String) {
        self.extensionID = extensionID
        self.displayName = displayName
        self.keyID = keyID
        self.variant = variant
        self.sdkVariant = sdkVariant
        self.usageDescription = usageDescription
        self.hasOwnUI = hasOwnUI
        self.ownUIDescription = ownUIDescription
        self.usesThirdPartyModels = usesThirdPartyModels
        self.thirdPartyModels = thirdPartyModels
        self.dataLeavesDevice = dataLeavesDevice
        self.dataDestination = dataDestination
        self.contactEmail = contactEmail
    }

    /// Builds the Host slice's application field for the given key ID.
    /// The ID comes from the presented secret (see `submit(apiKeySecret:)`:
    /// extracted — unverified, naming only — from the secret the caller
    /// holds; the store verifies the secret authoritatively and binds
    /// only on a match). The secret itself is never a stored property:
    /// it lives only in the form's in-memory `SecureField` for the
    /// duration of the submit call. The comma-separated third-party
    /// model list is split into individual names.
    public func makeField(apiKeyID: UUID) -> SDKAssistApplication.Field {
        SDKAssistApplication.Field(
            extensionID: extensionID,
            displayName: displayName,
            apiKeyID: apiKeyID,
            sdkVariant: sdkVariant,
            usageDescription: usageDescription,
            hasOwnUI: hasOwnUI,
            ownUIDescription: ownUIDescription,
            usesThirdPartyModels: usesThirdPartyModels,
            thirdPartyModels: (thirdPartyModels ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            dataLeavesDevice: dataLeavesDevice,
            dataDestination: dataDestination,
            contactEmail: contactEmail)
    }

    /// Submits the application to the Host slice's
    /// `SDKAssistApplicationStore` (S-5): validates the fields, requires
    /// the extension to be installed, and verifies the presented secret
    /// against the Keychain-backed key store. The secret proves possession
    /// of the key the application binds to and is dropped after
    /// verification — the persisted record carries only the key ID.
    /// Returns the stored application (status `pending`); approval is a
    /// separate host action (`SDKAssistApplicationStore.approve`) that
    /// grants the entitlements by key ID alone. Throws `SDKError` on any
    /// failure — the secret is never included in an error. If this model
    /// names a key (`keyID`, the existing-application variant) and the
    /// presented secret names a different one, submission is rejected:
    /// the secret must belong to the key being bound.
    public func submit(apiKeySecret: String) async throws -> SDKAssistApplication {
        guard let idString = SDKAPIKeyCodec.extractPresentedKeyID(from: apiKeySecret),
              let apiKeyID = UUID(uuidString: idString) else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        if let namedKeyID = keyID, let named = UUID(uuidString: namedKeyID), named != apiKeyID {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        return try await SDKAssistApplicationStore.shared.submit(makeField(apiKeyID: apiKeyID), apiKeySecret: apiKeySecret)
    }

    /// Field errors keyed by field name, mirroring Legacy's form
    /// validation. Empty means submittable. The usage-description
    /// minimum matches the Host field rule
    /// (`SDKAssistApplication.minimumUsageDescriptionLength`).
    public func validationErrors() -> [String: String] {
        var errors: [String: String] = [:]
        if extensionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["extensionID"] = "Extension ID is required."
        }
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["displayName"] = "Display name is required."
        }
        if usageDescription.trimmingCharacters(in: .whitespacesAndNewlines).count < SDKAssistApplication.minimumUsageDescriptionLength {
            errors["usageDescription"] = "Describe the Assist usage (at least \(SDKAssistApplication.minimumUsageDescriptionLength) characters)."
        }
        if hasOwnUI, (ownUIDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["ownUIDescription"] = "Describe your own UI for Assist responses."
        }
        if usesThirdPartyModels, (thirdPartyModels ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["thirdPartyModels"] = "List the third-party models used."
        }
        if dataLeavesDevice, (dataDestination ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["dataDestination"] = "State where user data goes."
        }
        let email = contactEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty || !email.contains("@") || !email.contains(".") {
            errors["contactEmail"] = "A valid contact email is required."
        }
        return errors
    }
}

// MARK: - User logs
//
// Legacy: `SwiftCode/SDK/Runtime/Diagnostics/SDKUserLogger.swift`
// (sanitized in-memory entries) as read by `SDKStudioLogsView`'s User
// pane. Secrets are never logged: entries carry a redacted message only.
// The Developer pane reads SwiftCode's `DiagnosticsService`; the Audit pane
// has no SwiftCode equivalent yet (`SDKAuditLog` is Host slice) and is
// reported as such in the Studio spec draft.

public enum SDKStudioUserLogLevel: String, Sendable, Codable, CaseIterable {
    case info
    case warning
    case error
}

public struct SDKStudioUserLogEntry: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let level: SDKStudioUserLogLevel
    public let message: String
    public let correlationID: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), level: SDKStudioUserLogLevel,
                message: String, correlationID: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.correlationID = correlationID
    }
}

public final class SDKStudioUserLogger: @unchecked Sendable {
    public static let shared = SDKStudioUserLogger()
    private let lock = NSLock()
    private var entries: [SDKStudioUserLogEntry] = []
    public static let maxEntries = 500

    public init() {}

    public func log(level: SDKStudioUserLogLevel, message: String, correlationID: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        entries.append(SDKStudioUserLogEntry(level: level, message: message, correlationID: correlationID))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    public func info(_ message: String, correlationID: String? = nil) {
        log(level: .info, message: message, correlationID: correlationID)
    }

    public func warning(_ message: String, correlationID: String? = nil) {
        log(level: .warning, message: message, correlationID: correlationID)
    }

    public func error(_ message: String, correlationID: String? = nil) {
        log(level: .error, message: message, correlationID: correlationID)
    }

    public func recentEntries(limit: Int = 200) -> [SDKStudioUserLogEntry] {
        lock.lock(); defer { lock.unlock() }
        return Array(entries.suffix(limit))
    }

    public func entries(matching query: String) -> [SDKStudioUserLogEntry] {
        lock.lock(); defer { lock.unlock() }
        let needle = query.lowercased()
        return entries.filter {
            $0.message.lowercased().contains(needle)
                || ($0.correlationID ?? "").lowercased().contains(needle)
        }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}
