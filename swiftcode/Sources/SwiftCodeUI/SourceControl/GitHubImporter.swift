import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

public final class GitHubImporter: @unchecked Sendable {
    public static let shared = GitHubImporter()
    private init() {}

    private let fm = FileManager.default

    private var projectsRoot: URL {
        let useCustom = UserDefaults.standard.bool(forKey: "saveProjectsOnCustomFolder")
        if useCustom {
            let customPath = UserDefaults.standard.string(forKey: "customProjectsFolder") ?? ""
            if !customPath.isEmpty {
                return URL(fileURLWithPath: customPath)
            }
        }
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects")
    }

    private var gitHubClient: GitHubClient {
        let store = defaultSecretStore()
        return GitHubClient(tokenProvider: { store.readString(SecretAccount.githubToken) })
    }

    public func importRepository(from urlString: String, branch: String = "main") async throws -> SCProject {
        let (owner, repo) = try parseRepoURL(urlString)
        return try await importRepository(owner: owner, repo: repo, branch: branch)
    }

    public func importRepository(owner: String, repo: String, branch: String = "main") async throws -> SCProject {
        guard let token = defaultSecretStore().readString(SecretAccount.githubToken), !token.isEmpty else {
            throw GitHubImporterError.notAuthenticated
        }

        let zipData = try await gitHubClient.downloadRepositoryZip(owner: owner, repo: repo, branch: branch)
        let zipURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try zipData.write(to: zipURL)
        defer { try? fm.removeItem(at: zipURL) }

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try extractArchive(zipURL, to: tempDir)

        let extractedRoot = try findExtractedRoot(in: tempDir)

        let projectsDir = projectsRoot
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        var finalName = sanitizeName(repo)
        var destDir = projectsDir.appendingPathComponent(finalName)
        var counter = 2
        while fm.fileExists(atPath: destDir.path) {
            finalName = "\(sanitizeName(repo)) \(counter)"
            destDir = projectsDir.appendingPathComponent(finalName)
            counter += 1
        }

        try copyContents(from: extractedRoot, to: destDir)

        let fileTree = buildFileTree(at: destDir, relativeTo: destDir)

        var project = SCProject(name: finalName, directoryURL: destDir)
        project.githubRepo = "https://github.com/\(owner)/\(repo)"
        project.files = fileTree
        project.fileCount = project.files.flatMap { $0.flattenedFiles() }.count

        let projectData = try SCProjectJSONManager.shared.encode(project)
        try SCProjectFileManager.shared.writeFile(data: projectData, to: destDir.appendingPathComponent("project.json"))

        try await ProjectRegistryStore.shared.note(rootURL: destDir, name: finalName, kind: .folder)

        return project
    }

    private func extractArchive(_ archive: URL, to destination: URL) throws {
        let unzipPath = "/usr/bin/unzip"
        guard fm.isExecutableFile(atPath: unzipPath) else {
            throw GitHubImporterError.extractionFailed
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: unzipPath)
        process.arguments = ["-q", "-o", archive.path, "-d", destination.path]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitHubImporterError.extractionFailed
        }
    }

    private func parseRepoURL(_ urlString: String) throws -> (owner: String, repo: String) {
        let cleaned = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parts = cleaned.split(separator: "/", maxSplits: 2)
        guard parts.count >= 2 else {
            throw GitHubImporterError.invalidURL(urlString)
        }
        let owner = String(parts[0])
        let repo = String(parts[1]).replacingOccurrences(of: ".git", with: "")
        guard !owner.isEmpty, !repo.isEmpty else {
            throw GitHubImporterError.invalidURL(urlString)
        }
        return (owner, repo)
    }

    private func findExtractedRoot(in directory: URL) throws -> URL {
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        if contents.count == 1,
           let single = contents.first,
           (try? single.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return single
        }
        return directory
    }

    private func copyContents(from source: URL, to destination: URL) throws {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )
        for item in contents {
            let itemName = item.lastPathComponent
            guard !itemName.contains(".."), !itemName.hasPrefix("/") else {
                throw GitHubImporterError.unsafePath(itemName)
            }
            let destItem = destination.appendingPathComponent(itemName)
            guard destItem.standardizedFileURL.path
                .hasPrefix(destination.standardizedFileURL.path) else {
                throw GitHubImporterError.unsafePath(itemName)
            }
            try fm.copyItem(at: item, to: destItem)
        }
    }

    private func buildFileTree(at url: URL, relativeTo base: URL) -> [SCProjectFileNode] {
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.lastPathComponent != "project.json" }
            .sorted {
                let aDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bDir = (try? $1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aDir != bDir { return aDir }
                return $0.lastPathComponent < $1.lastPathComponent
            }
            .map { child -> SCProjectFileNode in
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let basePath = base.standardizedFileURL.path
                let childPath = child.standardizedFileURL.path
                let relativePath = childPath.hasPrefix(basePath + "/")
                    ? String(childPath.dropFirst(basePath.count + 1))
                    : child.lastPathComponent
                let children = isDir ? buildFileTree(at: child, relativeTo: base) : []
                return SCProjectFileNode(name: child.lastPathComponent, path: relativePath, isDirectory: isDir, children: children)
            }
    }

    private let maxNameLength = 64

    private func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return name
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxNameLength)
            .description
    }
}

public enum GitHubImporterError: LocalizedError {
    case notAuthenticated
    case invalidURL(String)
    case unsafePath(String)
    case extractionFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "GitHub token not found. Please add your personal access token in Settings."
        case .invalidURL(let url):
            return "Invalid GitHub repository URL: \(url)"
        case .unsafePath(let path):
            return "Archive contains an unsafe file path: \(path)"
        case .extractionFailed:
            return "Failed to extract the repository archive."
        }
    }
}
