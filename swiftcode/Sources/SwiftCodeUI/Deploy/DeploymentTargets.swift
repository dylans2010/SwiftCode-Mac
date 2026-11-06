// Ported from Legacy `SwiftCode/Backend/Deployments/DeploymentTargets.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: FrameworkConfig, DeploymentTargets.

import Foundation
import SwiftCodeGitHub
import SwiftCodeIDECore

struct FrameworkConfig {
    let name: String
    let buildCommand: String?
    let outputDirectory: String
}

final class DeploymentTargets: @unchecked Sendable {
    static let shared = DeploymentTargets()
    private init() {}

    /// Prepares the repository for deployment by staging, committing, and pushing changes using GitHub API.
    func prepareRepositoryForDeployment(project: Project, logHandler: @escaping (String) -> Void) async throws -> Bool {
        logHandler("Initializing repository preparation workflow")

        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            logHandler("CRITICAL ERROR: No GitHub repository is linked to this project.")
            logHandler("Please go to Project Settings and connect a GitHub repository before deploying.")
            throw NSError(domain: "Deployment", code: 401, userInfo: [NSLocalizedDescriptionKey: "Deployment requires a connected GitHub repository containing the full project codebase."])
        }

        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)

        do {
            // Step 1: Check repository status
            logHandler("Checking GitHub repository status")
            let isEmpty = try await GitHubService.shared.isRepositoryEmpty(owner: owner, repo: repo)

            // Step 2: Initialize if empty
            if isEmpty {
                logHandler("Repository is empty, creating initial commit")
                try await GitHubService.shared.initializeRepository(owner: owner, repo: repo, branch: "main")
                logHandler("Initial commit created successfully")
            }

            // Step 3: Verify main branch exists
            let branch = try await GitHubService.shared.getBranch(owner: owner, repo: repo, branch: "main")
            if branch == nil {
                logHandler("Branch 'main' not found, attempting to create it")

                // Try to find any commit to branch from
                let commits = try await GitHubService.shared.listCommits(owner: owner, repo: repo, perPage: 1)
                if let latestCommit = commits.first {
                    try await GitHubService.shared.createBranchRef(owner: owner, repo: repo, branch: "main", sha: latestCommit.sha)
                    logHandler("Successfully created 'main' branch")
                } else {
                    logHandler("No commits found in repository, cannot create branch.")
                    throw NSError(domain: "Deployment", code: 404, userInfo: [NSLocalizedDescriptionKey: "Repository has no commits. Branch initialization failed."])
                }
            }

            // Step 4: Upload project codebase files
            logHandler("Uploading project files to repository")
            // Rewired (S-FLAGS): the ported `GitHubService.pushProject`
            // takes collected `files: [(path, data)]`, not a `Project` —
            // the Legacy call shape `pushProject(project, owner:repo:...)`
            // does not exist in production. Files are collected from the
            // project's `FileNode` tree exactly as Legacy's
            // `GitHubRepositoryManager.pushProject` did (text files only;
            // files that cannot be read as UTF-8 are skipped).
            let projectDir = await project.directoryURL
            let files = collectProjectFiles(from: project.files, projectDir: projectDir)
            try await GitHubService.shared.pushProject(
                owner: owner,
                repo: repo,
                branch: "main",
                commitMessage: "Deployment update: \(Date().formatted())",
                files: files
            )

            // Step 5: Confirm readiness
            logHandler("Repository preparation completed successfully")

            return true
        } catch {
            logHandler("FAILED to prepare repository: \(error.localizedDescription)")
            logHandler("Suggestion: Check your GitHub Personal Access Token permissions (needs 'repo' scope).")
            throw error
        }
    }

    /// Collects the project's files as `(path, data)` pairs for the Git
    /// Data API push, walking the `FileNode` tree exactly as Legacy's
    /// `GitHubRepositoryManager.pushProject` did (`collectFiles`). Only
    /// files readable as UTF-8 text are included — binary and unreadable
    /// files are skipped, as Legacy did.
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

    /// Detects the framework used in the project.
    func detectFramework(project: Project) async -> FrameworkConfig {
        let projectPath = await project.directoryURL.path
        let fileManager = FileManager.default

        // Detect Next.js
        if fileManager.fileExists(atPath: "\(projectPath)/next.config.js") ||
           fileManager.fileExists(atPath: "\(projectPath)/next.config.mjs") {
            return FrameworkConfig(name: "Next.js", buildCommand: "npm run build", outputDirectory: ".next")
        }

        // Detect Vite (React, Vue, etc.)
        if fileManager.fileExists(atPath: "\(projectPath)/vite.config.js") ||
           fileManager.fileExists(atPath: "\(projectPath)/vite.config.ts") {
            return FrameworkConfig(name: "Vite", buildCommand: "npm run build", outputDirectory: "dist")
        }

        // Detect Nuxt
        if fileManager.fileExists(atPath: "\(projectPath)/nuxt.config.js") ||
           fileManager.fileExists(atPath: "\(projectPath)/nuxt.config.ts") {
            return FrameworkConfig(name: "Nuxt", buildCommand: "npm run build", outputDirectory: ".output/public")
        }

        // Detect Astro
        if fileManager.fileExists(atPath: "\(projectPath)/astro.config.mjs") {
            return FrameworkConfig(name: "Astro", buildCommand: "npm run build", outputDirectory: "dist")
        }

        // Detect generic package.json
        if fileManager.fileExists(atPath: "\(projectPath)/package.json") {
            return FrameworkConfig(name: "Node.js", buildCommand: "npm run build", outputDirectory: "dist")
        }

        // Default to static
        return FrameworkConfig(name: "Static", buildCommand: nil, outputDirectory: ".")
    }

    /// Routes the deployment to the appropriate platform manager.
    func deploy(
        project: Project,
        platform: DeploymentPlatform,
        token: String?,
        domain: String?,
        logHandler: @escaping (String) -> Void
    ) async throws -> DeploymentResult {
        switch platform {
        case .netlify:
            logHandler("Starting Netlify deployment...")
            return try await NetlifyManager.shared.deploy(project: project, token: token, domain: domain, logHandler: logHandler)
        case .vercel:
            logHandler("Starting Vercel deployment...")
            return try await VercelManager.shared.deploy(project: project, token: token, domain: domain, logHandler: logHandler)
        case .githubPages:
            logHandler("Starting GitHub Pages deployment...")
            return try await GitHubPagesManager.shared.deploy(project: project, domain: domain, logHandler: logHandler)
        }
    }
}
