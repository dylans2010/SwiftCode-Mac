import Foundation
import SwiftCodeExtensions

public enum SDKExampleManager {
    public static let exampleID = "com.example.repository-build-extension"
    public static let exampleName = "Repository Build Extension"
    public static let exampleVersion = "0.1.0"
    public static let exampleDescription = "Comprehensive demonstration extension exercising source control, managed builds, project metadata, workspace file access, network requests, and security vault capabilities."
    public static let exampleSlug = "repository-build-extension"

    public static let templateDirectoryName = "extension-typescript"

    public enum SDKExampleError: Error, Sendable {
        case templateNotFound
        case invalidTemplate(String)
        case preparationFailed(String)
    }

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

    public static func managedExampleURL(projectsDirectory: URL? = nil) -> URL {
        (projectsDirectory ?? managedProjectsDirectory())
            .appendingPathComponent("RepositoryBuildExtension", isDirectory: true)
    }

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

        if !fm.fileExists(atPath: targetURL.path) {
            let projectsDir = targetURL.deletingLastPathComponent()
            do {
                try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
                try copyTemplate(from: sourceURL, to: targetURL)
            } catch {
                throw SDKExampleError.preparationFailed("Could not copy the example template: \(error.localizedDescription)")
            }
        } else {
            let targetManifest = targetURL.appendingPathComponent("swiftcode.json")
            if !fm.fileExists(atPath: targetManifest.path) {
                let sourceManifest = sourceURL.appendingPathComponent("swiftcode.json")
                if fm.fileExists(atPath: sourceManifest.path) {
                    try? copyInstantiatedFile(from: sourceManifest, to: targetManifest)
                }
            }
        }

        try validatePreparedExample(at: targetURL)
        return targetURL
    }

    private static let placeholders: [(String, String)] = [
        ("__EXTENSION_ID__", exampleID),
        ("__EXTENSION_NAME__", exampleName),
        ("__EXTENSION_VERSION__", exampleVersion),
        ("__EXTENSION_DESCRIPTION__", exampleDescription),
        ("__ID_SLUG__", exampleSlug),
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
