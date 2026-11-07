import Foundation
import SwiftUI

@MainActor
public final class SDKExampleManager: ObservableObject {
    public static let shared = SDKExampleManager()

    private init() {}

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

        if !fm.fileExists(atPath: targetURL.path) {
            try fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
            try fm.copyItem(at: sourceURL, to: targetURL)
        } else {
            let targetManifest = targetURL.appendingPathComponent("swiftcode.json")
            if !fm.fileExists(atPath: targetManifest.path) {
                let sourceManifest = sourceURL.appendingPathComponent("swiftcode.json")
                if fm.fileExists(atPath: sourceManifest.path) {
                    try? fm.copyItem(at: sourceManifest, to: targetManifest)
                }
            }
        }

        let manifestURL = targetURL.appendingPathComponent("swiftcode.json")
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw NSError(
                domain: "SwiftCode.SDKExample",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Example configuration file swiftcode.json is missing."]
            )
        }

        let project = try await ProjectSessionStore.shared.importProject(from: targetURL, name: "Repository Build Extension")

        await ProjectSessionStore.shared.openProject(project)

        return project
    }
}
