import Foundation
import SwiftUI

@MainActor
public final class GitHubGistService: ObservableObject {
    public static let shared = GitHubGistService()
    private init() {}

    @Published public var gists: [GistResponse] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?

    private let baseURL = URL(string: "https://api.github.com")!

    private var token: String? {
        APIKeyManager.shared.retrieveKey(service: .gitHub) ?? KeychainService.shared.get(forKey: KeychainService.githubToken)
    }

    private func authorizedRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GistError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GistError.apiError("GitHub API error \(http.statusCode): \(body)")
        }
    }


    private func normalizedFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func sanitize(_ files: [GistFile]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: files.compactMap { file in
            guard let name = normalizedFilename(file.filename) else { return nil }
            return (name, file.content)
        })
    }

    public func cloneURL(for gist: GistResponse, useSSH: Bool) -> String {
        if useSSH {
            if let push = gist.gitPushUrl, !push.isEmpty {
                return push
            }
            return "git@gist.github.com:\(gist.id).git"
        }

        if let pull = gist.gitPullUrl, !pull.isEmpty {
            return pull
        }
        return "https://gist.github.com/\(gist.id).git"
    }

    public func uploadFilesToGist(id: String, urls: [URL]) async throws -> GistResponse {
        var imported: [String: GistUpdateRequest.FileUpdateContent?] = [:]

        for url in urls {
            let entries = try collectFileEntries(from: url)
            for entry in entries {
                imported[entry.name] = .init(content: entry.content)
            }
        }

        guard !imported.isEmpty else {
            throw GistError.apiError("No readable files found in selection.")
        }

        return try await updateGist(id: id, description: nil, files: imported)
    }

    private func collectFileEntries(from url: URL) throws -> [(name: String, content: String)] {
        let needsScoped = url.startAccessingSecurityScopedResource()
        defer { if needsScoped { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory == true {
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var output: [(name: String, content: String)] = []
            while let item = enumerator?.nextObject() as? URL {
                let itemValues = try item.resourceValues(forKeys: [.isDirectoryKey])
                guard itemValues.isDirectory != true else { continue }
                if let content = try? String(contentsOf: item) {
                    output.append((item.lastPathComponent, content))
                }
            }
            return output
        }

        guard let content = try? String(contentsOf: url) else { return [] }
        return [(url.lastPathComponent, content)]
    }

    // MARK: - API Methods

    public func fetchGists() async throws -> [GistResponse] {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("gists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "50")]

        let request = authorizedRequest(url: components.url!)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

            let decodedGists = try decoder().decode([GistResponse].self, from: data)
            self.gists = decodedGists
            return decodedGists
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func fetchGist(id: String) async throws -> GistResponse {
        errorMessage = nil
        do {
            let url = baseURL.appendingPathComponent("gists/\(id)")
        let request = authorizedRequest(url: url)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response, data: data)
            return try decoder().decode(GistResponse.self, from: data)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func createGist(files: [GistFile], description: String, isPublic: Bool) async throws -> GistResponse {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let url = baseURL.appendingPathComponent("gists")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fileDict = sanitize(files)
        guard !fileDict.isEmpty else { throw GistError.apiError("Please name at least one file before creating a gist.") }

        let body = CreateGistRequest(description: description, isPublic: isPublic, files: fileDict)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

            let newGist = try decoder().decode(GistResponse.self, from: data)
            self.gists.insert(newGist, at: 0)
            return newGist
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func updateGist(id: String, description: String?, files: [String: GistUpdateRequest.FileUpdateContent?]) async throws -> GistResponse {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let url = baseURL.appendingPathComponent("gists/\(id)")
        var request = authorizedRequest(url: url, method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GistUpdateRequest(description: description, files: files)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

            let updatedGist = try decoder().decode(GistResponse.self, from: data)
            if let index = gists.firstIndex(where: { $0.id == id }) {
                gists[index] = updatedGist
            }
            return updatedGist
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func deleteGist(id: String) async throws {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let url = baseURL.appendingPathComponent("gists/\(id)")
        let request = authorizedRequest(url: url, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw GistError.invalidResponse }
        guard http.statusCode == 204 || (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GistError.apiError("GitHub API error \(http.statusCode): \(body)")
        }

            gists.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func checkIsStarred(id: String) async throws -> Bool {
        let url = baseURL.appendingPathComponent("gists/\(id)/star")
        let request = authorizedRequest(url: url)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 204
    }

    public func starGist(id: String) async throws {
        errorMessage = nil
        do {
            let url = baseURL.appendingPathComponent("gists/\(id)/star")
            let request = authorizedRequest(url: url, method: "PUT")
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response, data: data)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func unstarGist(id: String) async throws {
        errorMessage = nil
        do {
            let url = baseURL.appendingPathComponent("gists/\(id)/star")
        let request = authorizedRequest(url: url, method: "DELETE")
        let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { throw GistError.invalidResponse }
            guard http.statusCode == 204 || (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw GistError.apiError("GitHub API error \(http.statusCode): \(body)")
            }
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    public func forkGist(id: String) async throws -> GistResponse {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let url = baseURL.appendingPathComponent("gists/\(id)/forks")
        let request = authorizedRequest(url: url, method: "POST")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)

            let forkedGist = try decoder().decode(GistResponse.self, from: data)
            self.gists.insert(forkedGist, at: 0)
            return forkedGist
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Comments

    public func fetchComments(gistId: String) async throws -> [GistComment] {
        let url = baseURL.appendingPathComponent("gists/\(gistId)/comments")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decoder().decode([GistComment].self, from: data)
    }

    public func createComment(gistId: String, body: String) async throws -> GistComment {
        let url = baseURL.appendingPathComponent("gists/\(gistId)/comments")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["body": body]
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decoder().decode(GistComment.self, from: data)
    }

    // MARK: - Revisions

    public func fetchRevisions(gistId: String) async throws -> [GistRevision] {
        let url = baseURL.appendingPathComponent("gists/\(gistId)/commits")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decoder().decode([GistRevision].self, from: data)
    }

    public func fetchGistAtRevision(gistId: String, sha: String) async throws -> GistResponse {
        let url = baseURL.appendingPathComponent("gists/\(gistId)/\(sha)")
        let request = authorizedRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response, data: data)
        return try decoder().decode(GistResponse.self, from: data)
    }

    // MARK: - Download

    public func downloadGistZip(gistId: String) async throws -> URL {
        let gist = try await fetchGist(id: gistId)
        let revision = gist.history?.first?.version ?? "HEAD"
        guard let zipURL = URL(string: "https://gist.github.com/\(gist.id)/archive/\(revision).zip") else {
            throw GistError.apiError("Invalid Gist URL for download")
        }

        let request = authorizedRequest(url: zipURL)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GistError.apiError("Failed to download ZIP archive")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(gistId)-\(revision).zip")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}
