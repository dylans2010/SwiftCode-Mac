import Foundation

final class GitHubPagesManager {
    static let shared = GitHubPagesManager()
    private init() {}

    private let baseURL = URL(string: "https://api.github.com")!

    func deploy(
        project: Project,
        domain: String?,
        logHandler: @escaping (String) -> Void
    ) async throws -> DeploymentResult {
        guard let repoURL = project.githubRepo, !repoURL.isEmpty else {
            return DeploymentResult(success: false, url: nil, errorMessage: "GitHub repository not connected.")
        }

        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(repoURL)
        let token = DeploymentKeychainManager.shared.retrieveKey(service: .github)

        do {
            logHandler("Starting GitHub Pages deployment workflow for project: \(project.name)")
            logHandler("Target Repository: \(owner)/\(repo)")

            logHandler("Ensuring GitHub repository is up to date...")
            let repoPrepared = try await prepareGitHubRepository(project: project, logHandler: logHandler)
            guard repoPrepared else {
                return DeploymentResult(success: false, url: nil, errorMessage: "Failed to prepare GitHub repository for deployment.")
            }

            logHandler("Checking existing GitHub Pages configuration...")
            let pagesInfo = try? await getPagesInfo(owner: owner, repo: repo, token: token)

            if pagesInfo == nil {
                logHandler("GitHub Pages is not currently enabled for this repository.")
                logHandler("Enabling GitHub Pages via API (build_type: workflow)...")
                try await enablePages(owner: owner, repo: repo, token: token, logHandler: logHandler)
                logHandler("✓ GitHub Pages enabled successfully.")
            } else {
                logHandler("✓ GitHub Pages is already enabled.")
            }

            logHandler("Verifying GitHub Actions deployment workflow (.github/workflows/pages.yml)...")
            try await ensurePagesWorkflow(project: project, owner: owner, repo: repo, token: token, logHandler: logHandler)

            logHandler("Entering deployment monitoring phase...")
            logHandler("Waiting for GitHub Actions to trigger and complete deployment...")
            let finalStatus = try await pollDeploymentStatus(owner: owner, repo: repo, token: token, logHandler: logHandler)

            if finalStatus == "succeeded" {
                logHandler("Fetching final site metadata...")
                let finalPagesInfo = try await getPagesInfo(owner: owner, repo: repo, token: token)
                let siteURL = domain != nil ? "https://\(domain!)" : finalPagesInfo.htmlUrl
                logHandler("✓ DEPLOYMENT SUCCESSFUL: \(siteURL)")
                return DeploymentResult(success: true, url: siteURL, errorMessage: nil)
            } else {
                logHandler("CRITICAL ERROR: GitHub Pages deployment failed or timed out.")
                logHandler("Polling returned status: \(finalStatus)")
                return DeploymentResult(success: false, url: nil, errorMessage: "GitHub Pages deployment failed or timed out.")
            }
        } catch {
            logHandler("DEPLOYMENT FAILED: \(error.localizedDescription)")
            logHandler("Detailed Error Context: \(error)")
            return DeploymentResult(success: false, url: nil, errorMessage: error.localizedDescription)
        }
    }

    private func prepareGitHubRepository(project: Project, logHandler: @escaping (String) -> Void) async throws -> Bool {
        let (owner, repo) = try GitHubRepositoryManager.shared.parseRepoURL(project.githubRepo!)

        logHandler("Uploading project files to GitHub repository")
        try await GitHubService.shared.pushProject(
            project,
            owner: owner,
            repo: repo,
            commitMessage: "GitHub Pages Deployment: \(Date().formatted())",
            branch: "main"
        )
        return true
    }

    private func getPagesInfo(owner: String, repo: String, token: String?) async throws -> GitHubPagesInfo {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/pages")
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GitHubPagesManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Pages not found or error fetching info."])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubPagesInfo.self, from: data)
    }

    private func enablePages(owner: String, repo: String, token: String?, logHandler: @escaping (String) -> Void) async throws {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/pages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "build_type": "workflow",
            "source": [
                "branch": "main",
                "path": "/"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "GitHubPagesManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to enable Pages: \(errorMsg)"])
        }
        logHandler("GitHub Pages enabled successfully.")
    }

    private func ensurePagesWorkflow(project: Project, owner: String, repo: String, token: String?, logHandler: @escaping (String) -> Void) async throws {
        let path = ".github/workflows/pages.yml"

        // Check if workflow already exists using GitHubService (API based)
        let existingSHA = try? await GitHubService.shared.getFileSHA(owner: owner, repo: repo, path: path, branch: "main")
        if existingSHA != nil {
            return
        }

        let framework = await detectFramework(project: project)
        let buildSteps = generateBuildSteps(for: framework)

        let workflowContent = """
name: Deploy to GitHub Pages
on:
  push:
    branches: ["main"]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
\(buildSteps)
      - name: Setup Pages
        uses: actions/configure-pages@v4
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: '\(framework.outputDirectory == "." ? "." : framework.outputDirectory)'
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
"""
        // Push file using GitHubService (API based)
        try await GitHubService.shared.pushFile(
            owner: owner,
            repo: repo,
            path: path,
            content: workflowContent,
            message: "Add GitHub Pages deployment workflow",
            branch: "main"
        )
        logHandler("Created .github/workflows/pages.yml with \(framework.name) configuration.")
    }

    private func detectFramework(project: Project) async -> FrameworkConfig {
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
        return FrameworkConfig(name: "Static", buildCommand: nil, outputDirectory: ".")
    }

    private func generateBuildSteps(for framework: FrameworkConfig) -> String {
        if let buildCommand = framework.buildCommand {
            return """
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: 'npm'
      - name: Install dependencies
        run: npm install
      - name: Build
        run: \(buildCommand)
"""
        }
        return ""
    }

    private func pollDeploymentStatus(owner: String, repo: String, token: String?, logHandler: @escaping (String) -> Void) async throws -> String {
        let url = baseURL.appendingPathComponent("repos/\(owner)/\(repo)/pages/deployments")

        for _ in 1...60 { // Poll for 10 minutes (10s intervals)
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let deployments = try JSONDecoder().decode(GitHubPagesDeploymentsResponse.self, from: data)
                if let latest = deployments.deployments.first {
                    logHandler("Status: \(latest.status ?? "unknown")")
                    if latest.status == "succeed" { return "succeeded" }
                    if ["fail", "cancel"].contains(latest.status) { return "failed" }
                }
            }

            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        return "timed_out"
    }
}

// MARK: - GitHub Pages Models

struct GitHubPagesInfo: Codable {
    let url: String
    let status: String?
    let htmlUrl: String
}

struct GitHubPagesDeploymentsResponse: Codable {
    let deployments: [GitHubPagesDeployment]
}

struct GitHubPagesDeployment: Codable {
    let id: String?
    let status: String?
}
