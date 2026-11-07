import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeSubprocess

public enum DeploymentPlatform: String, Codable, CaseIterable, Sendable {
    case netlify = "Netlify"
    case vercel = "Vercel"
    case githubPages = "GitHub Pages"

    public var id: String { rawValue }

    var tokenAccount: String {
        switch self {
        case .netlify: return SecretAccount.netlifyToken
        case .vercel: return SecretAccount.vercelToken
        case .githubPages: return SecretAccount.githubToken
        }
    }
}

public struct DeploymentResult: Sendable, Equatable {
    public var success: Bool
    public var url: String?
    public var errorMessage: String?

    public init(success: Bool, url: String? = nil, errorMessage: String? = nil) {
        self.success = success
        self.url = url
        self.errorMessage = errorMessage
    }
}

public struct DeploymentFramework: Sendable, Equatable {
    public var name: String
    public var buildCommand: String?
    public var outputDirectory: String

    public init(name: String, buildCommand: String?, outputDirectory: String) {
        self.name = name
        self.buildCommand = buildCommand
        self.outputDirectory = outputDirectory
    }

    public static func detect(in folder: URL) -> DeploymentFramework {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(name).path) }
        if exists("next.config.js") || exists("next.config.mjs") {
            return DeploymentFramework(name: "Next.js", buildCommand: "npm run build", outputDirectory: ".next")
        }
        if exists("vite.config.js") || exists("vite.config.ts") {
            return DeploymentFramework(name: "Vite", buildCommand: "npm run build", outputDirectory: "dist")
        }
        if exists("nuxt.config.js") || exists("nuxt.config.ts") {
            return DeploymentFramework(name: "Nuxt", buildCommand: "npm run build", outputDirectory: ".output/public")
        }
        if exists("astro.config.mjs") {
            return DeploymentFramework(name: "Astro", buildCommand: "npm run build", outputDirectory: "dist")
        }
        if exists("package.json") {
            return DeploymentFramework(name: "Node.js", buildCommand: "npm run build", outputDirectory: "dist")
        }
        return DeploymentFramework(name: "Static", buildCommand: nil, outputDirectory: ".")
    }

    var buildSteps: String {
        guard let buildCommand else { return "" }
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
}

public enum DeploymentError: Error, LocalizedError, Equatable {
    case missingToken(DeploymentPlatform)
    case noGitRepository
    case invalidRemote(String)
    case pushFailed(String)
    case invalidToken(DeploymentPlatform)
    case providerError(String)
    case pagesFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken(let p):
            return "No \(p.rawValue) token is stored. Add one in the Deploy window first."
        case .noGitRepository:
            return "This folder is not a git repository with an origin remote."
        case .invalidRemote(let url):
            return "The origin remote (\(url)) is not a github.com repository."
        case .pushFailed(let output):
            return "git push failed: \(output)"
        case .invalidToken(let p):
            return "The stored \(p.rawValue) token was rejected by \(p.rawValue). Check it and try again."
        case .providerError(let message):
            return message
        case .pagesFailed(let message):
            return message
        }
    }
}

public struct GitPushClient: Sendable {
    public var remoteURL: @Sendable (URL) -> String?
    public var push: @Sendable (URL) async throws -> Void

    public init(remoteURL: @escaping @Sendable (URL) -> String?,
                push: @escaping @Sendable (URL) async throws -> Void) {
        self.remoteURL = remoteURL
        self.push = push
    }

    public static func live(store: SecretStore) -> GitPushClient {
        GitPushClient(
            remoteURL: { folder in Self.runGit(["remote", "get-url", "origin"], in: folder)?.trimmingCharacters(in: .whitespacesAndNewlines) },
            push: { folder in
                if let remote = Self.runGit(["remote", "get-url", "origin"], in: folder),
                   let path = Self.gitHubHTTPSPath(remote) {
                    Self.seedGitHubCredential(githubHTTPSPath: path, token: store.readString(SecretAccount.githubToken), in: folder)
                }
                let output = await Task.detached {
                    Self.runGitWithOutput(["push"], in: folder)
                }.value
                guard let output else { throw DeploymentError.pushFailed("git could not be started") }
                guard output.status == 0 else {
                    throw DeploymentError.pushFailed(String((output.stdout + output.stderr).suffix(1000)))
                }
            })
    }

    static func gitHubHTTPSPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://"), !trimmed.contains(" "),
              let components = URLComponents(string: trimmed),
              let host = components.host, host.lowercased() == "github.com",
              components.user == nil, components.password == nil else { return nil }
        let path = components.path
        guard !path.isEmpty, path != "/" else { return "" }
        return String(path.dropFirst())
    }

    static func seedGitHubCredential(githubHTTPSPath path: String?, token: String?, in directory: URL) {
        guard let path,
              let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return }
        var lines = ["protocol=https", "host=github.com"]
        if !path.isEmpty { lines.append("path=\(path)") }
        lines.append("username=x-access-token")
        lines.append("password=<redacted>")
        let input = lines.joined(separator: "\n") + "\n\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HostTool.path("git"))
        process.arguments = ["credential", "approve"]
        process.currentDirectoryURL = directory
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try stdin.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            return
        }
    }

    static func runGit(_ arguments: [String], in folder: URL) -> String? {
        guard let out = runGitWithOutput(arguments, in: folder), out.status == 0 else { return nil }
        return out.stdout
    }

    static func runGitWithOutput(_ arguments: [String], in folder: URL) -> (status: Int32, stdout: String, stderr: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HostTool.path("git"))
        process.arguments = arguments
        process.currentDirectoryURL = folder
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }
}

public struct GitHubPagesInfo: Codable, Sendable, Equatable {
    public var url: String
    public var status: String?
    public var htmlUrl: String
}

public struct GitHubPagesDeployment: Codable, Sendable, Equatable {
    public var id: Int?
    public var status: String?
}

struct GitHubPagesDeploymentsResponse: Codable {
    var deployments: [GitHubPagesDeployment]
}

public struct DeploymentService: Sendable {
    public var session: URLSession
    public var store: SecretStore
    public var git: GitPushClient

    public var pagesPollAttempts = 12
    public var pagesPollInterval: TimeInterval = 5

    public init(session: URLSession = .shared, store: SecretStore,
                git: GitPushClient? = nil) {
        self.session = session
        self.store = store
        self.git = git ?? .live(store: store)
    }

    public func token(for platform: DeploymentPlatform) -> String? {
        store.readString(platform.tokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func deploy(platform: DeploymentPlatform, workspaceFolder: URL, domain: String?,
                       log: @escaping @Sendable (String) -> Void) async throws -> DeploymentResult {
        let customDomain = (domain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = token(for: platform), !token.isEmpty else {
            throw DeploymentError.missingToken(platform)
        }
        guard let remote = git.remoteURL(workspaceFolder), !remote.isEmpty else {
            throw DeploymentError.noGitRepository
        }
        guard let (owner, repo) = GitHubRepoReference.parseRemoteURL(remote) else {
            throw DeploymentError.invalidRemote(remote)
        }
        let framework = DeploymentFramework.detect(in: workspaceFolder)
        log("Starting \(platform.rawValue) deployment for \(owner)/\(repo) (\(framework.name)).")

        switch platform {
        case .netlify, .vercel:
            try await validateProviderToken(platform: platform, token: token)
            log("Token validated with \(platform.rawValue).")
            log("Pushing the current branch to GitHub — \(platform.rawValue) builds from its GitHub integration.")
            try await git.push(workspaceFolder)
            log("✓ Changes pushed to GitHub.")
            let url = customDomain.isEmpty ? platform.dashboardURL : "https://\(customDomain)"
            log("✓ Deployment triggered. Check the \(platform.rawValue) dashboard for the build status.")
            return DeploymentResult(success: true, url: url)
        case .githubPages:
            log("Ensuring the GitHub repository is up to date...")
            try await git.push(workspaceFolder)
            log("Checking existing GitHub Pages configuration...")
            let pagesInfo = try? await getPagesInfo(owner: owner, repo: repo, token: token)
            if pagesInfo == nil {
                log("GitHub Pages is not currently enabled for this repository. Enabling via API (build_type: workflow)...")
                try await enablePages(owner: owner, repo: repo, token: token)
                log("✓ GitHub Pages enabled.")
            } else {
                log("✓ GitHub Pages is already enabled.")
            }
            log("Verifying the GitHub Actions deployment workflow (.github/workflows/pages.yml)...")
            try await ensurePagesWorkflow(owner: owner, repo: repo, token: token, framework: framework)
            log("Waiting for GitHub Actions to deploy...")
            let status = try await pollDeploymentStatus(owner: owner, repo: repo, token: token, log: log)
            if status == "succeed" {
                let final = try await getPagesInfo(owner: owner, repo: repo, token: token)
                let siteURL = customDomain.isEmpty ? final.htmlUrl : "https://\(customDomain)"
                log("✓ DEPLOYMENT SUCCESSFUL: \(siteURL)")
                return DeploymentResult(success: true, url: siteURL)
            }
            throw DeploymentError.pagesFailed("GitHub Pages deployment \(status == "timed_out" ? "timed out" : "failed") (status: \(status)).")
        }
    }

    func validateProviderToken(platform: DeploymentPlatform, token: String) async throws {
        let url: URL = {
            switch platform {
            case .netlify: return URL(string: "https://api.netlify.com/api/v1/user")!
            case .vercel: return URL(string: "https://api.vercel.com/v2/user")!
            case .githubPages: return URL(string: "https://api.github.com/user")!
            }
        }()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DeploymentError.providerError("No response from \(platform.rawValue).")
        }
        switch http.statusCode {
        case 200: return
        case 401, 403: throw DeploymentError.invalidToken(platform)
        default: throw DeploymentError.providerError("\(platform.rawValue) returned HTTP \(http.statusCode) while validating the token.")
        }
    }

    func gitHubRequest(path: String, method: String = "GET", token: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/\(path)")!)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    func getPagesInfo(owner: String, repo: String, token: String) async throws -> GitHubPagesInfo {
        let (data, response) = try await session.data(for: gitHubRequest(path: "repos/\(owner)/\(repo)/pages", token: token))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DeploymentError.providerError("GitHub Pages is not enabled for \(owner)/\(repo).")
        }
        return try decode(GitHubPagesInfo.self, from: data)
    }

    func enablePages(owner: String, repo: String, token: String) async throws {
        let body: [String: Any] = ["build_type": "workflow", "source": ["branch": "main", "path": "/"]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await session.data(for: gitHubRequest(path: "repos/\(owner)/\(repo)/pages", method: "POST", token: token, body: data))
        guard let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
            throw DeploymentError.providerError("Failed to enable GitHub Pages for \(owner)/\(repo) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
    }

    func ensurePagesWorkflow(owner: String, repo: String, token: String, framework: DeploymentFramework) async throws {
        let path = ".github/workflows/pages.yml"
        let (getData, getResponse) = try await session.data(for: gitHubRequest(path: "repos/\(owner)/\(repo)/contents/\(path)?ref=main", token: token))
        var sha: String?
        if let http = getResponse as? HTTPURLResponse, http.statusCode == 200,
           let json = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
           let existingSHA = json["sha"] as? String {
            sha = existingSHA
        }
        guard sha == nil else { return }
        let content = pagesWorkflowContent(framework: framework)
        var body: [String: Any] = [
            "message": "Add GitHub Pages deployment workflow",
            "content": Data(content.utf8).base64EncodedString(),
            "branch": "main",
        ]
        if let sha { body["sha"] = sha }
        let data = try JSONSerialization.data(withJSONObject: body)
        let (_, putResponse) = try await session.data(for: gitHubRequest(path: "repos/\(owner)/\(repo)/contents/\(path)", method: "PUT", token: token, body: data))
        guard let http = putResponse as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
            throw DeploymentError.providerError("Failed to create .github/workflows/pages.yml (HTTP \((putResponse as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
    }

    func pagesWorkflowContent(framework: DeploymentFramework) -> String {
        """
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
        \(framework.buildSteps)
              - name: Setup Pages
                uses: actions/configure-pages@v4
              - name: Upload artifact
                uses: actions/upload-pages-artifact@v3
                with:
                  path: '\(framework.outputDirectory)'
              - name: Deploy to GitHub Pages
                id: deployment
                uses: actions/deploy-pages@v4
        """
    }

    func pollDeploymentStatus(owner: String, repo: String, token: String, log: @escaping @Sendable (String) -> Void) async throws -> String {
        for _ in 1...max(1, pagesPollAttempts) {
            let (data, response) = try await session.data(for: gitHubRequest(path: "repos/\(owner)/\(repo)/pages/deployments", token: token))
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let decoded = try? decode(GitHubPagesDeploymentsResponse.self, from: data),
               let latest = decoded.deployments.first {
                let status = latest.status ?? "unknown"
                log("Status: \(status)")
                if status == "succeed" { return "succeed" }
                if ["fail", "cancel"].contains(status) { return status }
            }
            try await Task.sleep(nanoseconds: UInt64(pagesPollInterval * 1_000_000_000))
        }
        return "timed_out"
    }
}

extension DeploymentPlatform {
    var dashboardURL: String {
        switch self {
        case .netlify: return "https://app.netlify.com"
        case .vercel: return "https://vercel.com/dashboard"
        case .githubPages: return "https://github.com"
        }
    }
}
