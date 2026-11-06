import Foundation
import Observation

/// Project dashboard — Legacy's `Views/Dashboard/` folder organisation and
/// GitHub remote setup, ported onto SwiftCode's systems.
///
/// - Folders group the projects SwiftCode already knows (`RecentProjects` +
///   `ProjectRegistryStore`); the folder membership itself is JSON in
///   Application Support `SwiftCode/ProjectDashboard/folders.json`.
/// - Per-project symbols keep Legacy's UserDefaults key
///   (`com.swiftcode.project.symbol.<uuid>`) so a symbol chosen in Legacy
///   survives the move.
/// - GitHub remote setup calls `api.github.com` directly with a caller
///   supplied token (wiring: pass the token SwiftCodeGitHub already holds in
///   the Keychain). Linking a remote runs real `git remote add` in the
///   project directory; every failure is surfaced, never swallowed.

public struct ProjectFolder: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var projectPaths: [String]
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, projectPaths: [String] = [], createdAt: Date = Date()) {
        self.id = id; self.name = name; self.projectPaths = projectPaths; self.createdAt = createdAt
    }
}

@Observable
@MainActor
public final class ProjectFolderStore {
    public private(set) var folders: [ProjectFolder] = []
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        let base = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? base.appendingPathComponent("SwiftCode/ProjectDashboard/folders.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        folders = (try? JSONDecoder().decode([ProjectFolder].self, from: data)) ?? []
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(folders) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func createFolder(name: String) -> ProjectFolder {
        let folder = ProjectFolder(name: name)
        folders.append(folder)
        save()
        return folder
    }

    public func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        save()
    }

    public func addProject(_ url: URL, to folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        if !folders[idx].projectPaths.contains(url.path) {
            folders[idx].projectPaths.append(url.path)
            save()
        }
    }

    public func removeProject(_ url: URL, from folderID: UUID) {
        guard let idx = folders.firstIndex(where: { $0.id == folderID }) else { return }
        folders[idx].projectPaths.removeAll { $0 == url.path }
        save()
    }

    public func projects(in folder: ProjectFolder, allProjects: [URL]) -> [URL] {
        allProjects.filter { folder.projectPaths.contains($0.path) }
    }
}

public enum ProjectDashboardSymbols {
    /// Legacy's per-project symbol key, kept verbatim for compatibility.
    public static func symbol(for projectID: UUID, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: "com.swiftcode.project.symbol.\(projectID.uuidString)") ?? "swift"
    }

    public static func setSymbol(_ symbol: String, for projectID: UUID, defaults: UserDefaults = .standard) {
        defaults.set(symbol, forKey: "com.swiftcode.project.symbol.\(projectID.uuidString)")
    }
}

/// GitHub remote setup (Legacy `GitHubRemoteSetupView`'s data layer).
@Observable
@MainActor
public final class GitHubRemoteSetupModel {
    public struct RepositorySummary: Identifiable, Sendable, Hashable {
        public var id: Int { githubID }
        public let githubID: Int
        public let name: String
        public let fullName: String
        public let htmlURL: String
        public let isPrivate: Bool
    }

    public enum SetupError: Error, LocalizedError {
        case noToken
        case requestFailed(String)
        case gitFailed(String)
        public var errorDescription: String? {
            switch self {
            case .noToken: return "A GitHub token is required. Add one in Settings ▸ Accounts first."
            case .requestFailed(let message): return message
            case .gitFailed(let message): return message
            }
        }
    }

    public var token: String?
    public private(set) var availableRepos: [RepositorySummary] = []
    public private(set) var isLoadingRepos = false
    public private(set) var repoLoadError: String?

    public init(token: String? = nil) { self.token = token }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let token, !token.isEmpty else { throw SetupError.noToken }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SetupError.requestFailed("GitHub returned HTTP \(status).")
        }
        return data
    }

    public func loadRepositories() async {
        isLoadingRepos = true
        repoLoadError = nil
        defer { isLoadingRepos = false }
        do {
            let url = URL(string: "https://api.github.com/user/repos?per_page=100&sort=updated")!
            let data = try await request(url)
            struct Repo: Decodable { var id: Int; var name: String; var full_name: String; var html_url: String; var `private`: Bool }
            let repos = try JSONDecoder().decode([Repo].self, from: data)
            availableRepos = repos.map { RepositorySummary(githubID: $0.id, name: $0.name, fullName: $0.full_name, htmlURL: $0.html_url, isPrivate: $0.private) }
        } catch {
            repoLoadError = error.localizedDescription
        }
    }

    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> RepositorySummary {
        let url = URL(string: "https://api.github.com/user/repos")!
        let body = try JSONSerialization.data(withJSONObject: ["name": name, "description": description, "private": isPrivate])
        let data = try await request(url, method: "POST", body: body)
        struct Repo: Decodable { var id: Int; var name: String; var full_name: String; var html_url: String; var `private`: Bool }
        let repo = try JSONDecoder().decode(Repo.self, from: data)
        return RepositorySummary(githubID: repo.id, name: repo.name, fullName: repo.full_name, htmlURL: repo.html_url, isPrivate: repo.private)
    }

    /// Runs real `git remote add origin <url>` in the project directory.
    public func linkRemote(projectURL: URL, remoteURL: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectURL.path, "remote", "add", "origin", remoteURL]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SetupError.gitFailed(err.isEmpty ? "git remote add failed with status \(process.terminationStatus)." : err)
        }
    }
}
