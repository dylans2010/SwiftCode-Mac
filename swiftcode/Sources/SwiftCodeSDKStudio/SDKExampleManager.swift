import Foundation
import SwiftCodeExtensions

// MARK: - SDKExampleManager
//
// Ported from Legacy `SwiftCode/SDK/Studio/Views/SDKExampleManager.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// WHAT IT DOES:
// 1. Resolves the bundled example source: Legacy launched the concrete
//    `RepositoryBuildExtension` project from
//    `SwiftCode/SDK/Examples/RepositoryBuildExtension`. SwiftCode ships no
//    bundled example project — the example files live on as spec
//    reference material only (ledger rows 10449–10466, IMPLEMENTED as
//    reference) — so the manager resolves the real minimal extension
//    project from the destination's SDK templates,
//    `sdk/templates/extension-typescript`, and instantiates it with the
//    example's identity (id, name, version, description verbatim from
//    Legacy's `swiftcode.json`). The result is a real, working minimal
//    extension, not a fake example: it has the example's id and the
//    template's two starter commands (`inspect-repository`, `run-build`)
//    and capabilities (`source-control.read`, `build.execute`). The full
//    seven-command Legacy example is NOT reproduced here — its files are
//    spec reference material, and re-copying them as a bundled project
//    would contradict the ledger.
// 2. Prepares a writable user-managed copy at
//    `~/Library/Application Support/SwiftCode/Projects/RepositoryBuildExtension`
//    (Linux: `~/.config/swiftcode/projects/RepositoryBuildExtension`)
//    without modifying the template source.
// 3. Validates the required manifests (`swiftcode.json` via the strict
//    validator, `package.json`, `src/index.ts`).
// 4. Handles duplicate calls gracefully: reuses the existing managed
//    example, repairing a missing manifest from the template.
// 5. Returns the managed project directory URL. Opening it in the
//    workspace is the app shell's job — SwiftCode has no `ProjectSessionStore`
//    (Legacy step 3–4); the Studio Projects view opens the returned URL
//    in the code editor.

public enum SDKExampleManager {
    /// Legacy example identity, verbatim from
    /// `SwiftCode/SDK/Examples/RepositoryBuildExtension/swiftcode.json`.
    public static let exampleID = "com.example.repository-build-extension"
    public static let exampleName = "Repository Build Extension"
    public static let exampleVersion = "0.1.0"
    public static let exampleDescription = "Comprehensive demonstration extension exercising source control, managed builds, project metadata, workspace file access, network requests, and security vault capabilities."
    /// npm package name for the instantiated example (Legacy's
    /// `package.json` name).
    public static let exampleSlug = "repository-build-extension"

    /// The template directory resolved by `defaultTemplateURL()`.
    public static let templateDirectoryName = "extension-typescript"

    public enum SDKExampleError: Error, Sendable {
        case templateNotFound
        case invalidTemplate(String)
        case preparationFailed(String)
    }

    /// Resolves the example template directory: the app bundle's
    /// `SwiftCodeSDK/Templates/extension-typescript` first (when the
    /// templates ship as bundle resources), then a `sdk/templates/`
    /// tree found by walking up from the current directory (dev
    /// checkout — covers both a repo-root and a `swiftcode/` working
    /// directory). Returns nil when no template is found.
    public static func defaultTemplateURL() -> URL? {
        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("SwiftCodeSDK/Templates/\(templateDirectoryName)", isDirectory: true),
           fm.fileExists(atPath: resourceURL.appendingPathComponent("swiftcode.json").path) {
            return resourceURL
        }
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("sdk/templates/\(templateDirectoryName)", isDirectory: true)
            if fm.fileExists(atPath: candidate.appendingPathComponent("swiftcode.json").path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            guard parent != dir else { break }
            dir = parent
        }
        return nil
    }

    /// The user-managed projects directory.
    public static func managedProjectsDirectory() -> URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("SwiftCode/Projects", isDirectory: true)
        #else
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("swiftcode/projects", isDirectory: true)
        #endif
    }

    /// The managed copy's location (`<projects>/RepositoryBuildExtension`).
    public static func managedExampleURL(projectsDirectory: URL? = nil) -> URL {
        (projectsDirectory ?? managedProjectsDirectory())
            .appendingPathComponent("RepositoryBuildExtension", isDirectory: true)
    }

    /// Prepares, validates, and returns the managed example project
    /// directory. Copies the template on first use (instantiating the
    /// `__EXTENSION_*__` placeholders with the example identity);
    /// reuses the existing copy afterwards, repairing a missing
    /// manifest from the template. Throws `SDKExampleError` when the
    /// template cannot be found or the prepared copy fails validation.
    @discardableResult
    public static func prepareExampleProject(
        templateURL: URL? = nil,
        projectsDirectory: URL? = nil
    ) throws -> URL {
        guard let sourceURL = templateURL ?? defaultTemplateURL() else {
            throw SDKExampleError.templateNotFound
        }
        let fm = FileManager.default
        let targetURL = managedExampleURL(projectsDirectory: projectsDirectory)

        // 1. Copy the template to the managed location if not present,
        //    instantiating placeholders as the files are written.
        if !fm.fileExists(atPath: targetURL.path) {
            let projectsDir = targetURL.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
                try copyTemplate(from: sourceURL, to: targetURL)
            } catch {
                throw SDKExampleError.preparationFailed("Could not copy the example template: \(error.localizedDescription)")
            }
        } else {
            // Repair the essential manifest if missing.
            let targetManifest = targetURL.appendingPathComponent("swiftcode.json")
            if !fm.fileExists(atPath: targetManifest.path) {
                let sourceManifest = sourceURL.appendingPathComponent("swiftcode.json")
                if fm.fileExists(atPath: sourceManifest.path) {
                    try? copyInstantiatedFile(from: sourceManifest, to: targetManifest)
                }
            }
        }

        // 2. Validate the required configuration.
        try validatePreparedExample(at: targetURL)
        return targetURL
    }

    // MARK: - Private

    private static let placeholders: [(String, String)] = [
        ("__EXTENSION_ID__", exampleID),
        ("__EXTENSION_NAME__", exampleName),
        ("__EXTENSION_VERSION__", exampleVersion),
        ("__EXTENSION_DESCRIPTION__", exampleDescription),
        ("__ID_SLUG__", exampleSlug),
        // The managed example is self-contained: the SDK dependency
        // resolves from the registry, like the Studio scaffold's
        // no-sdkPackage rule (`"@swiftcode/sdk": "^1.0.0"`). No local
        // file: path exists for a user-managed copy.
        ("__SDK_FILE_URL__", "^1.0.0"),
    ]

    private static func instantiate(_ text: String) -> String {
        var result = text
        for (placeholder, value) in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        return result
    }

    private static func copyTemplate(from source: URL, to target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw SDKExampleError.invalidTemplate("Could not read the template directory.")
        }
        for case let fileURL as URL in enumerator {
            let relative = fileURL.path.dropFirst(source.path.count + 1)
            guard !relative.isEmpty else { continue }
            let destination = target.appendingPathComponent(String(relative))
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try copyInstantiatedFile(from: fileURL, to: destination)
            }
        }
    }

    private static func copyInstantiatedFile(from source: URL, to destination: URL) throws {
        let data = try Data(contentsOf: source)
        if let text = String(data: data, encoding: .utf8) {
            try instantiate(text).write(to: destination, atomically: true, encoding: .utf8)
        } else {
            // Non-UTF-8 content (none in the template today) copies verbatim.
            try data.write(to: destination, options: [.atomic])
        }
    }

    private static func validatePreparedExample(at targetURL: URL) throws {
        let fm = FileManager.default
        let manifestURL = targetURL.appendingPathComponent("swiftcode.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw SDKExampleError.invalidTemplate("Example configuration file swiftcode.json is missing.")
        }
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw SDKExampleError.invalidTemplate("Could not read swiftcode.json: \(error.localizedDescription)")
        }
        let manifest: SwiftCodeManifest
        do {
            manifest = try SwiftCodeManifestValidator.validate(data: manifestData)
        } catch {
            throw SDKExampleError.invalidTemplate("The prepared example manifest failed validation: \(error.localizedDescription)")
        }
        guard manifest.id == exampleID else {
            throw SDKExampleError.invalidTemplate("The prepared example manifest has id \(manifest.id), expected \(exampleID).")
        }
        guard fm.fileExists(atPath: targetURL.appendingPathComponent("package.json").path) else {
            throw SDKExampleError.invalidTemplate("Example package.json is missing.")
        }
        guard fm.fileExists(atPath: targetURL.appendingPathComponent("src/index.ts").path) else {
            throw SDKExampleError.invalidTemplate("Example entrypoint src/index.ts is missing.")
        }
    }
}
