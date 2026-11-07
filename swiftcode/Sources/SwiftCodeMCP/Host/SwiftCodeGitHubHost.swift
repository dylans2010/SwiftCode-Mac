import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
    static var gitHubTestSecretStore: SecretStore?

    static var gitHubTestSession: URLSession?

    static func gitHubSecretStore() -> SecretStore {
        gitHubTestSecretStore ?? defaultSecretStore()
    }

    func gitHubClient() -> GitHubClient {
        let store = Self.gitHubSecretStore()
        let session = Self.gitHubTestSession ?? URLSession.shared
        return GitHubClient(session: session, tokenProvider: { [store] in
            let raw = store.readString(SecretAccount.githubToken)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.flatMap { $0.isEmpty ? nil : $0 }
        })
    }

    func gitHubStoredToken() -> String? {
        let raw = Self.gitHubSecretStore().readString(SecretAccount.githubToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.flatMap { $0.isEmpty ? nil : $0 }
    }

    func requireGitHubToken() throws {
        guard gitHubStoredToken() != nil else { throw GitHubError.missingToken }
    }

    nonisolated static func gitHubToolError(_ error: Error) -> MCPToolError {
        if let githubError = error as? GitHubError {
            return MCPToolError(githubError.localizedDescription)
        }
        return MCPToolError("GitHub request failed: \(error.localizedDescription)")
    }

    func resolveGitHubRepo(_ call: MCPToolCall, _ s: WorkspaceSession) throws -> (owner: String, repo: String) {
        if let raw = call.string("repository") {
            guard let ref = GitHubRepoReference.parse(raw) else {
                throw MCPToolError("Invalid repository \"\(raw)\". Use the form owner/repo.")
            }
            return ref
        }
        let root = Self.folder(of: s.model)
        let origin = try Self.runGit(["remote", "get-url", "origin"], in: root)
        if origin.status == 0 {
            let url = origin.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                if let ref = GitHubRepoReference.parseRemoteURL(url) { return ref }
                throw MCPToolError("The workspace's git remote 'origin' (\(url)) is not a github.com repository: pass a 'repository' argument (\"owner/repo\"), or run this in a workspace whose origin is a github.com remote.")
            }
        }
        throw MCPToolError("No repository given: pass a 'repository' argument (\"owner/repo\"), or run this in a workspace whose git remote 'origin' is a github.com repository.")
    }

    func resolveGitHubRepoReference(owner: String?, repo: String?, url: String?) throws -> (owner: String, repo: String) {
        let owner = owner?.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = repo?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let owner, !owner.isEmpty, let repo, !repo.isEmpty {
            guard let ref = GitHubRepoReference.parse("\(owner)/\(repo)") else {
                throw MCPToolError("Invalid repository \"\(owner)/\(repo)\". Use the form owner/repo.")
            }
            return ref
        }
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Provide 'owner' + 'repo', or a GitHub repository 'url'.")
        }
        if let ref = GitHubRepoReference.parseRemoteURL(raw) { return ref }
        if let parsed = URL(string: raw), parsed.host?.lowercased() == "github.com" {
            let segments = parsed.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            if segments.count >= 2, let ref = GitHubRepoReference.parse("\(segments[0])/\(segments[1])") {
                return ref
            }
        }
        throw MCPToolError("Could not parse owner/repo from '\(raw)'. Provide 'owner' + 'repo', or a github.com repository URL.")
    }
}
