import Foundation

enum DeploymentPlatform: String, Codable, CaseIterable, Identifiable {
    case netlify = "Netlify"
    case vercel = "Vercel"
    case githubPages = "GitHub Pages"

    var id: String { self.rawValue }
}

struct DeploymentResult {
    let success: Bool
    let url: String?
    let errorMessage: String?
}

struct FrameworkConfig {
    let name: String
    let buildCommand: String?
    let outputDirectory: String
}

final class DeploymentTargets: @unchecked Sendable {
    static let shared = DeploymentTargets()
    private init() {}

    func prepareRepositoryForDeployment(project: Project, logHandler: @escaping (String) -> Void) async throws -> Bool {
        logHandler("Initializing repository preparation workflow")

        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            logHandler("CRITICAL ERROR: No GitHub repository is linked to this project.")
            logHandler("Please go to Project Settings and connect a GitHub repository before deploying.")
            throw NSError(domain: "Deployment", code: 401, userInfo: [NSLocalizedDescriptionKey: "Deployment requires a connected GitHub repository containing the full project codebase."])
        }

        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)

        do {
            logHandler("Checking GitHub repository status")
            let isEmpty = try await GitHubService.shared.isRepositoryEmpty(owner: owner, repo: repo)

            if isEmpty {
                logHandler("Repository is empty, creating initial commit")
                try await GitHubService.shared.initializeRepository(owner: owner, repo: repo, branch: "main")
                logHandler("Initial commit created successfully")
            }

            let branch = try await GitHubService.shared.getBranch(owner: owner, repo: repo, branch: "main")
            if branch == nil {
                logHandler("Branch 'main' not found, attempting to create it")

                let commits = try await GitHubService.shared.listCommits(owner: owner, repo: repo, perPage: 1)
                if let latestCommit = commits.first {
                    try await GitHubService.shared.createBranchRef(owner: owner, repo: repo, branch: "main", sha: latestCommit.sha)
                    logHandler("Successfully created 'main' branch")
                } else {
                    logHandler("No commits found in repository, cannot create branch.")
                    throw NSError(domain: "Deployment", code: 404, userInfo: [NSLocalizedDescriptionKey: "Repository has no commits. Branch initialization failed."])
                }
            }

            logHandler("Uploading project files to repository")
            try await GitHubService.shared.pushProject(
                project,
                owner: owner,
                repo: repo,
                commitMessage: "Deployment update: \(Date().formatted())",
                branch: "main"
            )

            logHandler("Repository preparation completed successfully")

            return true
        } catch {
            logHandler("FAILED to prepare repository: \(error.localizedDescription)")
            logHandler("Suggestion: Check your GitHub Personal Access Token permissions (needs 'repo' scope).")
            throw error
        }
    }

    func detectFramework(project: Project) async -> FrameworkConfig {
        let projectPath = await project.directoryURL.path
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: "\(projectPath)/next.config.js") ||
           fileManager.fileExists(atPath: "\(projectPath)/next.config.mjs") {
            return FrameworkConfig(name: "Next.js", buildCommand: "npm run build", outputDirectory: ".next")
        }

        if fileManager.fileExists(atPath: "\(projectPath)/vite.config.js") ||
           fileManager.fileExists(atPath: "\(projectPath)/vite.config.ts") {
            return FrameworkConfig(name: "Vite", buildCommand: "npm run build", outputDirectory: "dist")
        }

        if fileManager.fileExists(atPath: "\(projectPath)/nuxt.config.js") ||
           fileManager.fileExists(atPath: "\(projectPath)/nuxt.config.ts") {
            return FrameworkConfig(name: "Nuxt", buildCommand: "npm run build", outputDirectory: ".output/public")
        }

        if fileManager.fileExists(atPath: "\(projectPath)/astro.config.mjs") {
            return FrameworkConfig(name: "Astro", buildCommand: "npm run build", outputDirectory: "dist")
        }

        if fileManager.fileExists(atPath: "\(projectPath)/package.json") {
            return FrameworkConfig(name: "Node.js", buildCommand: "npm run build", outputDirectory: "dist")
        }

        return FrameworkConfig(name: "Static", buildCommand: nil, outputDirectory: ".")
    }

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
