import Foundation
import ZIPFoundation

/// Downloads a GitHub repository archive and extracts it into the Projects directory.
///
/// After extraction, runs a project indexing scan and registers the project
/// in ProjectManager so it appears in the dashboard immediately.
final class GitHubImporter {
    static let shared = GitHubImporter()
    private init() {}

    private let fm = FileManager.default

    // MARK: - Import from URL String

    /// Import a repository from a GitHub URL such as "https://github.com/owner/repo".
    func importRepository(from urlString: String, branch: String = "main") async throws -> Project {
        let (owner, repo) = try parseRepoURL(urlString)
        return try await importRepository(owner: owner, repo: repo, branch: branch)
    }

    // MARK: - Import from Owner/Repo

    /// Import a repository by owner and repo name.
    func importRepository(owner: String, repo: String, branch: String = "main") async throws -> Project {
        guard GitHubAuth.shared.isAuthenticated else {
            throw GitHubImporterError.notAuthenticated
        }

        // 1. Download ZIP archive
        let zipURL = try await GitHubAPIBackend.shared.downloadRepositoryZip(
            owner: owner,
            repo: repo,
            branch: branch
        )
        defer { try? fm.removeItem(at: zipURL) }

        // 2. Extract to temporary directory
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: tempDir)

        // 3. Locate the extracted root (GitHub ZIPs wrap content in a single folder)
        let extractedRoot = try findExtractedRoot(in: tempDir)

        // 4. Build destination path: Documents/Projects/{repoName}
        let projectsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects")
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)

        var finalName = sanitizeName(repo)
        var destDir = projectsDir.appendingPathComponent(finalName)
        var counter = 2
        while fm.fileExists(atPath: destDir.path) {
            finalName = "\(sanitizeName(repo)) \(counter)"
            destDir = projectsDir.appendingPathComponent(finalName)
            counter += 1
        }

        // 5. Copy all extracted files into the project directory
        try copyContents(from: extractedRoot, to: destDir)

        // 6. Index the project — scan and build the file tree
        let fileTree = buildFileTree(at: destDir, relativeTo: destDir)

        // 7. Create project metadata
        var project = Project(name: finalName)
        project.githubRepo = "https://github.com/\(owner)/\(repo)"
        project.files = fileTree

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try encoder.encode(project)
        try metadata.write(to: destDir.appendingPathComponent("project.json"))

        // 8. Register in ProjectManager on main thread
        let registeredProject = project
        await MainActor.run {
            ProjectManager.shared.projects.insert(registeredProject, at: 0)
        }

        return registeredProject
    }

    // MARK: - Private Helpers

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

    private func buildFileTree(at url: URL, relativeTo base: URL) -> [FileNode] {
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
            .map { child -> FileNode in
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let basePath = base.standardizedFileURL.path
                let childPath = child.standardizedFileURL.path
                let relativePath = childPath.hasPrefix(basePath + "/")
                    ? String(childPath.dropFirst(basePath.count + 1))
                    : child.lastPathComponent
                let node = FileNode(name: child.lastPathComponent, path: relativePath, isDirectory: isDir)
                if isDir { node.children = buildFileTree(at: child, relativeTo: base) }
                return node
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

// MARK: - Errors

enum GitHubImporterError: LocalizedError {
    case notAuthenticated
    case invalidURL(String)
    case unsafePath(String)
    case extractionFailed

    var errorDescription: String? {
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
