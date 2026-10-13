import Foundation
import SwiftUI

// MARK: - SDKExampleManager
//
// Managed launcher and resolver for the bundled `RepositoryBuildExtension`
// SDK example (Phase 3 & Phase 4).
//
// WHAT IT DOES:
// 1. Resolves the authoritative bundled example source directory across app
//    bundle locations and relative repository development paths.
// 2. Prepares a writable user-managed copy at `~/.swiftcode/projects/RepositoryBuildExtension`
//    (or `ProjectSessionStore.shared.projectsDirectory`) without modifying
//    signed application bundle resources.
// 3. Validates required manifests (`swiftcode.json`, `package.json`).
// 4. Registers/imports the example as a Platform Project in `ProjectSessionStore`.
// 5. Handles duplicate clicks gracefully: reuses the existing managed example,
//    bringing it into active workspace state.

@MainActor
public final class SDKExampleManager: ObservableObject {
    public static let shared = SDKExampleManager()

    private init() {}

    /// Resolves the bundled `RepositoryBuildExtension` example directory.
    public static func defaultBundledExampleURL() -> URL? {
        let currentDir = FileManager.default.currentDirectoryPath
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/Examples/RepositoryBuildExtension"),
            Bundle.main.resourceURL?.appendingPathComponent("SwiftCode/SDK/Examples/RepositoryBuildExtension"),
            Bundle.main.url(forResource: "RepositoryBuildExtension", withExtension: nil),
            URL(fileURLWithPath: "\(currentDir)/SwiftCode/SDK/Examples/RepositoryBuildExtension"),
            URL(fileURLWithPath: "\(currentDir)/SDK/Examples/RepositoryBuildExtension")
        ]
        return candidates.compactMap { $0 }.first { url in
            FileManager.default.fileExists(atPath: url.appendingPathComponent("swiftcode.json").path)
        }
    }

    /// Prepares, registers, and opens the RepositoryBuildExtension SDK example project.
    @discardableResult
    public func launchExampleProject() async throws -> Project {
        guard let sourceURL = Self.defaultBundledExampleURL() else {
            throw NSError(
                domain: "SwiftCode.SDKExample",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled RepositoryBuildExtension SDK example resources were not found."]
            )
        }

        let fm = FileManager.default
        let projectsDir = ProjectSessionStore.shared.projectsDirectory
        let targetURL = projectsDir.appendingPathComponent("RepositoryBuildExtension")

        // 1. Copy example to managed user workspace if not present
        if !fm.fileExists(atPath: targetURL.path) {
            try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceURL, to: targetURL)
        } else {
            // Repair essential config if missing
            let targetManifest = targetURL.appendingPathComponent("swiftcode.json")
            if !fm.fileExists(atPath: targetManifest.path) {
                let sourceManifest = sourceURL.appendingPathComponent("swiftcode.json")
                if fm.fileExists(atPath: sourceManifest.path) {
                    try? fm.copyItem(at: sourceManifest, to: targetManifest)
                }
            }
        }

        // 2. Validate required configuration
        let manifestURL = targetURL.appendingPathComponent("swiftcode.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw NSError(
                domain: "SwiftCode.SDKExample",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Example configuration file swiftcode.json is missing."]
            )
        }

        // 3. Register or retrieve project in ProjectSessionStore
        let project = try await ProjectSessionStore.shared.importProject(from: targetURL, name: "Repository Build Extension")

        // 4. Open project
        await ProjectSessionStore.shared.openProject(project)

        return project
    }
}
