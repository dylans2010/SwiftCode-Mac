// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Deployments/VercelManager.swift
//   (Legacy main ab03f681) — verbatim except the adaptations below.
//
// Adaptations (production APIs differ from Legacy):
//   * `prepareGitHubRepository` called Legacy's
//     `GitHubService.pushProject(project, owner:repo:commitMessage:branch:)`.
//     That shape does not exist in production: `GitHubService.pushProject`
//     takes collected `files: [(path, data)]`. Files are collected from the
//     project's `FileNode` tree exactly as `DeploymentTargets`
//     (`SwiftCodeUI/Deploy/DeploymentTargets.swift`, S-FLAGS rewire) does —
//     text files only; files that cannot be read as UTF-8 are skipped.
//   * The `token` parameter is unused in the body, as in Legacy: the push
//     goes through `GitHubService`, whose token is configured at startup
//     (`GitHubService.shared.configure(tokenProvider:)`).
//
// Legacy behaviour kept verbatim: Vercel deploy is NOT a provider API
// upload — the manager only pushes the project to GitHub and returns a
// dashboard URL; Vercel's GitHub integration does the build.

import Foundation
import SwiftCodeGitHub
import SwiftCodeIDECore

final class VercelManager: @unchecked Sendable {
    static let shared = VercelManager()
    private init() {}

    func deploy(
        project: Project,
        token: String?,
        domain: String?,
        logHandler: @escaping (String) -> Void
    ) async throws -> DeploymentResult {
        do {
            logHandler("Starting Vercel deployment workflow for project: \(project.name)")
            logHandler("Vercel is configured to deploy via GitHub integration.")

            logHandler("Ensuring GitHub repository is up to date...")

            // Independent repository preparation
            let repoPrepared = try await prepareGitHubRepository(project: project, logHandler: logHandler)

            guard repoPrepared else {
                return DeploymentResult(success: false, url: nil, errorMessage: "Failed to prepare GitHub repository for deployment.")
            }

            logHandler("✓ Changes successfully pushed to GitHub.")
            logHandler("Vercel will now automatically pick up the new commit and start a deployment.")

            let siteURL = domain != nil ? "https://\(domain!)" : "https://vercel.com/dashboard"
            return DeploymentResult(success: true, url: siteURL, errorMessage: nil)
        } catch {
            logHandler("DEPLOYMENT FAILED: \(error.localizedDescription)")
            return DeploymentResult(success: false, url: nil, errorMessage: error.localizedDescription)
        }
    }

    private func prepareGitHubRepository(project: Project, logHandler: @escaping (String) -> Void) async throws -> Bool {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            logHandler("CRITICAL ERROR: No GitHub repository is linked to this project.")
            throw NSError(domain: "VercelManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Deployment requires a connected GitHub repository."])
        }

        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)

        logHandler("Syncing codebase to GitHub repository: \(owner)/\(repo)")
        let projectDir = await project.directoryURL
        let files = collectProjectFiles(from: project.files, projectDir: projectDir)
        try await GitHubService.shared.pushProject(
            owner: owner,
            repo: repo,
            branch: "main",
            commitMessage: "Vercel Deployment Sync: \(Date().formatted())",
            files: files
        )

        return true
    }

    /// Collects the project's files as `(path, data)` pairs for the Git
    /// Data API push — same walk as `DeploymentTargets.collectProjectFiles`
    /// (text files only; files that cannot be read as UTF-8 are skipped).
    private func collectProjectFiles(from nodes: [FileNode], projectDir: URL) -> [(path: String, data: Data)] {
        var collected: [(path: String, data: Data)] = []
        for node in nodes {
            if node.isDirectory {
                collected += collectProjectFiles(from: node.children, projectDir: projectDir)
                continue
            }
            let fileURL = projectDir.appendingPathComponent(node.path)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            collected.append((path: node.path, data: Data(content.utf8)))
        }
        return collected
    }
}
