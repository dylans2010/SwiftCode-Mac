// Tests for RepoPermManager's scope table (Legacy -> YcodeGitHub port).
// No network: only the scope -> human-readable/icon mapping is pinned.
// Static only: not executed here (no Swift toolchain in this environment).

import Foundation
import Testing
import YcodeGitHub

@Suite("RepoPermission scope table")
struct RepoPermManagerTests {

    @Test("Known scopes map to their descriptions and icons")
    func knownScopes() {
        let repo = RepoPermission.from(scope: "repo")
        #expect(repo.humanReadable == "Full Control Of Private Repositories")
        #expect(repo.icon == "folder.fill.badge.gearshape")

        let workflow = RepoPermission.from(scope: "workflow")
        #expect(workflow.humanReadable == "Update GitHub Actions Workflows")

        let readUser = RepoPermission.from(scope: "read:user")
        #expect(readUser.humanReadable == "Read All User Profile Data")

        let copilot = RepoPermission.from(scope: "copilot")
        #expect(copilot.humanReadable == "Full Control Of GitHub Copilot Settings")
    }

    @Test("Unknown scopes fall back to a title-cased scope and the open-lock icon")
    func unknownScopeFallback() {
        let unknown = RepoPermission.from(scope: "some_future_scope")
        #expect(unknown.humanReadable == "Some Future Scope")
        #expect(unknown.icon == "lock.open.fill")
        #expect(unknown.id == "some_future_scope")
    }

    @Test("Every documented scope has a mapping (no silent default)")
    func allDocumentedScopesMapped() {
        let scopes = ["repo", "repo:status", "repo_deployment", "public_repo", "repo:invite",
                      "security_events", "workflow", "write:packages", "read:packages",
                      "delete:packages", "admin:org", "write:org", "read:org",
                      "admin:public_key", "write:public_key", "read:public_key",
                      "admin:repo_hook", "write:repo_hook", "read:repo_hook", "admin:org_hook",
                      "user", "read:user", "user:email", "user:follow", "gist",
                      "notifications", "delete_repo", "write:discussion", "read:discussion",
                      "audit_log", "read:audit_log", "codespace", "copilot", "project",
                      "read:project", "admin:enterprise", "manage_runners:enterprise",
                      "manage_billing:enterprise", "read:enterprise"]
        for scope in scopes {
            let permission = RepoPermission.from(scope: scope)
            #expect(permission.icon != "lock.open.fill", "scope \(scope) fell through to the default")
            #expect(!permission.humanReadable.isEmpty)
        }
    }
}
