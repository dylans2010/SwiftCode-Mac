// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/RepoPermManager.swift
// Adapted for Ycode: RepoPermission scope table verbatim; the manager takes YcodeGitHub's tokenProvider (SecretStore-backed) instead of Legacy's KeychainService. ObservableObject -> @Observable.

import Foundation
import Observation

// MARK: - Repository Permission Model

public struct RepoPermission: Identifiable, Sendable {
    public var id: String { scope }
    public let scope: String
    public let humanReadable: String
    public let icon: String

    /// Maps a GitHub OAuth scope string to a human-readable description and icon.
    public static func from(scope: String) -> RepoPermission {
        switch scope {
        // Repo scopes
        case "repo":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Private Repositories", icon: "folder.fill.badge.gearshape")
        case "repo:status":
            return RepoPermission(scope: scope, humanReadable: "Access Commit Status", icon: "checkmark.circle.fill")
        case "repo_deployment":
            return RepoPermission(scope: scope, humanReadable: "Access Deployment Status", icon: "airplane")
        case "public_repo":
            return RepoPermission(scope: scope, humanReadable: "Access Public Repositories", icon: "globe")
        case "repo:invite":
            return RepoPermission(scope: scope, humanReadable: "Access Repository Invitations", icon: "envelope.fill")
        case "security_events":
            return RepoPermission(scope: scope, humanReadable: "Read And Write Security Events", icon: "shield.fill")
        // Workflow
        case "workflow":
            return RepoPermission(scope: scope, humanReadable: "Update GitHub Actions Workflows", icon: "gearshape.2.fill")
        // Packages
        case "write:packages":
            return RepoPermission(scope: scope, humanReadable: "Upload Packages To GitHub Package Registry", icon: "shippingbox.fill")
        case "read:packages":
            return RepoPermission(scope: scope, humanReadable: "Download Packages From GitHub Package Registry", icon: "shippingbox")
        case "delete:packages":
            return RepoPermission(scope: scope, humanReadable: "Delete Packages From GitHub Package Registry", icon: "shippingbox.fill")
        // Org scopes
        case "admin:org":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Organizations And Teams", icon: "building.2.fill")
        case "write:org":
            return RepoPermission(scope: scope, humanReadable: "Read And Write org/team Membership And Projects", icon: "person.3.fill")
        case "read:org":
            return RepoPermission(scope: scope, humanReadable: "Read org/team Membership And Projects", icon: "person.3")
        // Public key
        case "admin:public_key":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of User Public Keys", icon: "key.fill")
        case "write:public_key":
            return RepoPermission(scope: scope, humanReadable: "Write User Public Keys", icon: "key")
        case "read:public_key":
            return RepoPermission(scope: scope, humanReadable: "Read User Public Keys", icon: "key")
        // Hooks
        case "admin:repo_hook":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Repository Hooks", icon: "webhook")
        case "write:repo_hook":
            return RepoPermission(scope: scope, humanReadable: "Write Repository Hooks", icon: "webhook")
        case "read:repo_hook":
            return RepoPermission(scope: scope, humanReadable: "Read Repository Hooks", icon: "webhook")
        case "admin:org_hook":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Organization Webhooks", icon: "building.2.crop.circle")
        // User
        case "user":
            return RepoPermission(scope: scope, humanReadable: "Update All User Data", icon: "person.fill.badge.plus")
        case "read:user":
            return RepoPermission(scope: scope, humanReadable: "Read All User Profile Data", icon: "person.fill")
        case "user:email":
            return RepoPermission(scope: scope, humanReadable: "Access User Email Addresses", icon: "envelope")
        case "user:follow":
            return RepoPermission(scope: scope, humanReadable: "Follow And Unfollow Users", icon: "person.fill.badge.plus")
        // Misc
        case "gist":
            return RepoPermission(scope: scope, humanReadable: "Create Gists", icon: "doc.text.fill")
        case "notifications":
            return RepoPermission(scope: scope, humanReadable: "Access Notifications", icon: "bell.fill")
        case "delete_repo":
            return RepoPermission(scope: scope, humanReadable: "Delete Repositories", icon: "trash.fill")
        case "write:discussion":
            return RepoPermission(scope: scope, humanReadable: "Read And Write Team Discussions", icon: "bubble.left.and.bubble.right.fill")
        case "read:discussion":
            return RepoPermission(scope: scope, humanReadable: "Read Team Discussions", icon: "bubble.left.and.bubble.right")
        case "audit_log":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Audit Log", icon: "list.clipboard.fill")
        case "read:audit_log":
            return RepoPermission(scope: scope, humanReadable: "Read Audit Log", icon: "list.clipboard")
        case "codespace":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Codespaces", icon: "terminal.fill")
        case "copilot":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of GitHub Copilot Settings", icon: "sparkles")
        case "project":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Projects", icon: "checklist")
        case "read:project":
            return RepoPermission(scope: scope, humanReadable: "Read Access To Projects", icon: "checklist")
        case "admin:enterprise":
            return RepoPermission(scope: scope, humanReadable: "Full Control Of Enterprises", icon: "building.columns.fill")
        case "manage_runners:enterprise":
            return RepoPermission(scope: scope, humanReadable: "Manage Enterprise Runners And Runner Groups", icon: "server.rack")
        case "manage_billing:enterprise":
            return RepoPermission(scope: scope, humanReadable: "Read And Write Enterprise Billing Data", icon: "creditcard.fill")
        case "read:enterprise":
            return RepoPermission(scope: scope, humanReadable: "Read Enterprise Profile Data", icon: "building.columns")
        default:
            return RepoPermission(scope: scope, humanReadable: scope.replacingOccurrences(of: "_", with: " ").capitalized, icon: "lock.open.fill")
        }
    }
}

// MARK: - Repo Permission Manager

/// Reads the GitHub OAuth scopes granted to the signed-in token, by
/// inspecting the `X-OAuth-Scopes` response header of `GET /user`.
///
/// Legacy read the token from its own KeychainService. YcodeGitHub keeps
/// the token behind a `tokenProvider` (SecretStore-backed — see
/// `GitHubClient`), so this manager takes the same provider instead of
/// reaching for a keychain itself. Pass `GitHubClient`'s provider, or
/// `{ nil }` when no token is configured.
@Observable
@MainActor
public final class RepoPermManager: Sendable {
    public static let shared = RepoPermManager()
    private init() {}

    public var permissions: [RepoPermission] = []
    public var isLoading = false
    public var errorMessage: String?
    public var hasChecked = false

    private let baseURL = URL(string: "https://api.github.com")!

    /// Fetches the scopes for the stored GitHub token by inspecting the X-OAuth-Scopes response header.
    public func fetchPermissions(tokenProvider: @escaping @Sendable () -> String? = { nil }) async {
        guard let token = tokenProvider(), !token.isEmpty else {
            errorMessage = "No GitHub token configured. Add one in GitHub & Git Configuration."
            permissions = []
            hasChecked = true
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let url = baseURL.appendingPathComponent("user")
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200...299).contains(http.statusCode) else {
                let msg = http.statusCode == 401
                    ? "Invalid Or Expired Token."
                    : "GitHub API Error \(http.statusCode)."
                errorMessage = msg
                permissions = []
                isLoading = false
                hasChecked = true
                return
            }

            let scopesHeader = http.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? ""
            let scopes = scopesHeader
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            permissions = scopes.map { RepoPermission.from(scope: $0) }
            hasChecked = true
        } catch {
            errorMessage = error.localizedDescription
            permissions = []
            hasChecked = true
        }

        isLoading = false
    }
}
