import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

/// The GitHub API wiring for the MCP host (Wave 10, slice B): the
/// shared `GitHubClient`, repository resolution, and error mapping
/// for the seven Agentic GitHub tools (`create_pull_request`,
/// `review_pull_request`, `read_pull_request`, `read_issues`,
/// `create_issue`, `update_issue`, `search_issues`) and `github_repo`.
///
/// The token is optional for public reads and required for writes:
/// it is read fresh from the secret store on every request through
/// the client's `tokenProvider`, never cached here, never logged,
/// and never embedded in output or error messages. The client is
/// built fresh per call so tests can point it at a stub session;
/// `lastRateLimit` therefore reflects only the most recent call's
/// client and is not surfaced by the tools.
extension SwiftCodeMCPHost {
    /// Test seam for the GitHub token: when set, the secret store
    /// used instead of `defaultSecretStore()`. Tests set a
    /// `MemorySecretStore` so no real keychain or config file is
    /// touched; production never sets it. (Same shape as
    /// `agenticGitTestSecretStore`.)
    static var gitHubTestSecretStore: SecretStore?

    /// Test seam for the GitHub transport: when set, the session the
    /// client uses instead of `.shared`. Tests set a stub-protocol
    /// session (see `stubGitHub` in the test support); production
    /// never sets it.
    static var gitHubTestSession: URLSession?

    static func gitHubSecretStore() -> SecretStore {
        gitHubTestSecretStore ?? defaultSecretStore()
    }

    /// The shared GitHub API client: the stub session in tests, else
    /// `.shared`; the token is read fresh from the secret store on
    /// every request.
    func gitHubClient() -> GitHubClient {
        let store = Self.gitHubSecretStore()
        let session = Self.gitHubTestSession ?? URLSession.shared
        return GitHubClient(session: session, tokenProvider: { [store] in
            let raw = store.readString(SecretAccount.githubToken)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.flatMap { $0.isEmpty ? nil : $0 }
        })
    }

    /// The saved GitHub token, if any (read fresh at call time; a
    /// blank value counts as no token).
    func gitHubStoredToken() -> String? {
        let raw = Self.gitHubSecretStore().readString(SecretAccount.githubToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Fails with the client's `missingToken` error (whose message
    /// names the Settings place for the token) when no token is
    /// stored. Write tools call this BEFORE the approval gate, so a
    /// token-less write fails fast instead of asking for approval
    /// it cannot use.
    func requireGitHubToken() throws {
        guard gitHubStoredToken() != nil else { throw GitHubError.missingToken }
    }

    /// Converts a GitHub client failure into the tool error the
    /// model sees: the client's own message (it names the Settings
    /// place for the token, the rate-limit reset, and the failing
    /// repository), so the model can correct itself. The token
    /// never appears in it.
    nonisolated static func gitHubToolError(_ error: Error) -> MCPToolError {
        if let githubError = error as? GitHubError {
            return MCPToolError(githubError.localizedDescription)
        }
        return MCPToolError("GitHub request failed: \(error.localizedDescription)")
    }

    /// Resolves the `owner`/`repo` a GitHub tool acts on, in order:
    /// (a) an explicit `repository` argument ("owner/repo", parsed
    /// via `GitHubRepoReference.parse`); (b) the workspace git
    /// remote `origin` (`git remote get-url origin`, parsed via
    /// `GitHubRepoReference.parseRemoteURL`); (c) a failure naming
    /// both. No token is needed here: public reads work
    /// unauthenticated, and write tools check the token separately
    /// before the approval gate.
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

    /// Resolves `owner`+`repo` or a `url` for `github_repo`
    /// (Legacy's `resolveRepo`): explicit fields win; a URL is
    /// parsed as a github.com remote, leniently accepting
    /// `…/tree/…` and other suffixed paths the way Legacy did
    /// (only the first two path segments identify the repository).
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
