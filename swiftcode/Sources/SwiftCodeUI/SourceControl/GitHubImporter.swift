// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/GitHub/GitHubImport.swift — `GitHubImporter` +
//   `GitHubImporterError` (Legacy main ab03f681).
//
// Destination: SwiftCodeUI/SourceControl/GitHubImporter.swift (with
// `GitHubImportManager.swift` in the same directory).
//
// Why this is a port, not a covered file: the claimed-covered audit
// marked the import manager COVERED via a `GitHubImport.swift` that
// does not exist in main and the `git_clone` MCP tool. Neither covers
// it: `git_clone` clones a URL to a path, it does not resolve an
// owner/repo to a URL, download a GitHub archive, build a project
// record, or register the project — and no `GitHubImporter` /
// `GitHubImportManager` / `GitHubAuth` type exists anywhere in main.
// The behaviour (import a GitHub repo as a project in the dashboard)
// was genuinely missing, so both files are ported here.
//
// Adaptations (behaviour preserved unless noted):
// * `Project` -> `SCProject` (`SCProjectManifest.swift`): `init(name:
//   directoryURL:)`, `githubRepo`, `files: [SCProjectFileNode]`.
//   `buildFileTree` now builds `[SCProjectFileNode]` with the same
//   algorithm (hidden files skipped, `project.json` excluded, dirs
//   first, sorted by name). `fileCount` uses the destination's own
//   convention, `project.files.flatMap { $0.flattenedFiles() }.count`
//   (SCProjectFormat.swift:633).
// * `GitHubAuth.shared.isAuthenticated` does not exist in main. The
//   token is read the destination way —
//   `defaultSecretStore().readString(SecretAccount.githubToken)`
//   (the `GitHubOAuth` pattern) — and an empty token still throws
//   `.notAuthenticated`, preserving Legacy's requirement that an
//   import needs a token (private repos + GitHub rate limits).
// * `GitHubAPIBackend.shared.downloadRepositoryZip(...) -> URL`
//   does not exist in main. `GitHubClient.downloadRepositoryZip`
//   exists and returns the archive `Data`; the importer writes it to
//   a temp file and unzips that, keeping Legacy's temp-file cleanup.
// * `import ZIPFoundation` is dropped. Extraction follows the
//   destination's own cross-platform convention instead of
//   Foundation's Darwin-only `unzipItem`: `/usr/bin/unzip -q -o`
//   via `Foundation.Process`, the exact mechanism
//   `BackupEngine.systemExtractArchive` (SwiftCodeCloud) uses, so
//   this file compiles on Linux as well as macOS. A missing `unzip`
//   binary or a non-zero exit throws `.extractionFailed` —
//   Legacy's declared-but-never-thrown case.
// * The projects root is `CodingManager.projectsRoot`'s computation
//   (Documents/Projects, honouring the `saveProjectsOnCustomFolder` /
//   `customProjectsFolder` keys) mirrored here, because that property
//   is internal to SwiftCodeIDECore and this file lives in SwiftCodeUI.
//   If the property is ever made public, point `projectsRoot` at it.
// * `project.json` is written with the destination's own encoder,
//   `SCProjectJSONManager.shared.encode(_:)` (iso8601 dates, the
//   SCProjectFormat convention), via
//   `SCProjectFileManager.shared.writeFile(data:to:)`.
// * Registration: `ProjectSessionStore.shared.projects.insert(...)`
//   does not exist in main. The destination registry is
//   `ProjectRegistryStore.shared.note(rootURL:name:kind:)` (actor,
//   dedupes by rootURL, persists to ProjectRegistry.json). Kind is
//   `.folder` — the imported repo is an arbitrary folder until the
//   opener detects an .xcodeproj / Package.swift inside it.
// * `GitHubImporter` keeps `@unchecked Sendable`; members are public
//   (SwiftCodeUI is consumed by the swiftcode-ide executable).

import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

/// Downloads a GitHub repository archive and extracts it into the Projects directory.
///
/// After extraction, runs a project indexing scan and registers the project
/// in the project registry so it appears in the dashboard immediately.
public final class GitHubImporter: @unchecked Sendable {
    public static let shared = GitHubImporter()
    private init() {}

    private let fm = FileManager.default

    /// Mirrors `CodingManager.projectsRoot` (SwiftCodeIDECore, internal):
    /// Documents/Projects, honouring the custom-projects-folder keys.
    /// See the file header — point this at the property if it is made public.
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

    // MARK: - Import from URL String

    /// Import a repository from a GitHub URL such as "https://github.com/owner/repo".
    public func importRepository(from urlString: String, branch: String = "main") async throws -> SCProject {
        let (owner, repo) = try parseRepoURL(urlString)
        return try await importRepository(owner: owner, repo: repo, branch: branch)
    }

    // MARK: - Import from Owner/Repo

    /// Import a repository by owner and repo name.
    public func importRepository(owner: String, repo: String, branch: String = "main") async throws -> SCProject {
        guard let token = defaultSecretStore().readString(SecretAccount.githubToken), !token.isEmpty else {
            throw GitHubImporterError.notAuthenticated
        }

        // 1. Download ZIP archive
        let zipData = try await gitHubClient.downloadRepositoryZip(owner: owner, repo: repo, branch: branch)
        let zipURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try zipData.write(to: zipURL)
        defer { try? fm.removeItem(at: zipURL) }

        // 2. Extract to temporary directory
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try extractArchive(zipURL, to: tempDir)

        // 3. Locate the extracted root (GitHub ZIPs wrap content in a single folder)
        let extractedRoot = try findExtractedRoot(in: tempDir)

        // 4. Build destination path: Documents/Projects/{repoName}
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

        // 5. Copy all extracted files into the project directory
        try copyContents(from: extractedRoot, to: destDir)

        // 6. Index the project — scan and build the file tree
        let fileTree = buildFileTree(at: destDir, relativeTo: destDir)

        // 7. Create project metadata
        var project = SCProject(name: finalName, directoryURL: destDir)
        project.githubRepo = "https://github.com/\(owner)/\(repo)"
        project.files = fileTree
        project.fileCount = project.files.flatMap { $0.flattenedFiles() }.count

        let projectData = try SCProjectJSONManager.shared.encode(project)
        try SCProjectFileManager.shared.writeFile(data: projectData, to: destDir.appendingPathComponent("project.json"))

        // 8. Register in the project registry so it appears in the dashboard
        try await ProjectRegistryStore.shared.note(rootURL: destDir, name: finalName, kind: .folder)

        return project
    }

    // MARK: - Private Helpers

    /// Extracts `archive` into `destination` via `/usr/bin/unzip`
    /// (`-q -o`), the destination's cross-platform extraction
    /// convention (`BackupEngine.systemExtractArchive`). Throws
    /// `.extractionFailed` when `unzip` is absent or exits non-zero.
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

// MARK: - Errors

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
