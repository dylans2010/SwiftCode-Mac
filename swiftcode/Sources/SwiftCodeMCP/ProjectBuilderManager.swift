import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub

/// Manages generation of user-project build files via XcodeGen
/// (Legacy `SwiftCode/Services/ProjectBuilderManager.swift`, Dylan's
/// own code, ported under MIT).
///
/// Adapted: Legacy took a `Project` model that does not exist in the
/// destination; the entry points take the project directory, the
/// project name, and the GitHub repo URL explicitly. The GitHub
/// calls go through the destination's `GitHubClient` (its
/// `createBranch` and branch-aware `getFileSHA` were added for this
/// manager — the destination had `getFileSHA` / `pushFile` /
/// `listBranches` but no branch creation). `parseRepoURL` is
/// Legacy's `GitHubRepositoryManager.parseRepoURL`, verbatim.
/// `runXcodeGen` is Legacy's disabled local generation: it throws
/// unless the spec is missing or the opt-in env var is set, and
/// never runs xcodegen itself.
///
/// Wiring: no lifecycle hook — a shared manager the project-open
/// flow calls (`prepareXcodeFiles`) and the remote-generation UI
/// calls (`triggerRemoteGeneration`). The workflow content comes
/// from the caller: Legacy read `build-project.yml` from
/// `SwiftCode/Backend/CI Building/build-project.yml`; the app loads
/// that template from its bundle and passes it in.
@MainActor
public final class ProjectBuilderManager: Sendable {
    public static let shared = ProjectBuilderManager()
    private init() {}

    private let fm = FileManager.default

    /// The GitHub client, replaceable for tests. Defaults to the
    /// shared client that reads the token fresh from the secret
    /// store on every request (`SecretAccount.githubToken`), the
    /// same client the MCP GitHub tools use.
    public var githubClient: GitHubClient

    public init(githubClient: GitHubClient? = nil) {
        if let githubClient {
            self.githubClient = githubClient
        } else {
            let store = defaultSecretStore()
            self.githubClient = GitHubClient(tokenProvider: { [store] in
                let raw = store.readString(SecretAccount.githubToken)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.flatMap { $0.isEmpty ? nil : $0 }
            })
        }
    }

    public enum BuilderError: Error, LocalizedError {
        case notLinkedToGitHub
        case missingWorkflowTemplate
        case invalidRepoURL(String)
        case missingProjectSpec(URL)

        public var errorDescription: String? {
            switch self {
            case .notLinkedToGitHub:
                return "Project is not linked to a GitHub repository."
            case .missingWorkflowTemplate:
                return "Could not find build-project.yml template."
            case .invalidRepoURL(let url):
                return "Invalid GitHub repository URL: \(url)"
            case .missingProjectSpec(let url):
                return "Missing project.yml at \(url.path); unable to continue project file preparation."
            }
        }
    }

    // MARK: - Public Entry Points

    public func prepareXcodeFiles(projectDir: URL, projectName: String) {
        guard !hasBuildArtifacts(in: projectDir, projectName: projectName) else { return }

        // Local generation is disabled in favor of GitHub Actions remote generation.
        // This method now serves as a fallback or a way to ensure basic structure.
        do {
            try ensureSubdirectories(in: projectDir)
        } catch {
            print("ProjectBuilderManager: Failed to ensure subdirectories: \(error.localizedDescription)")
        }
    }

    public func hasXcodeProjectFiles(in directory: URL) -> Bool {
        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return false }

        return contents.contains { $0.pathExtension == "xcodeproj" }
    }

    public func hasBuildArtifacts(in projectDir: URL, projectName: String) -> Bool {
        let xcodeProj = projectDir.appendingPathComponent("\(projectName).xcodeproj")
        let workspace = projectDir.appendingPathComponent("\(projectName).xcworkspace")

        if fm.fileExists(atPath: xcodeProj.path), fm.fileExists(atPath: workspace.path) {
            return true
        }

        // Xcode always stores an internal workspace within the project bundle.
        let internalWorkspace = xcodeProj
            .appendingPathComponent("project.xcworkspace")
            .appendingPathComponent("contents.xcworkspacedata")
        return fm.fileExists(atPath: xcodeProj.path) && fm.fileExists(atPath: internalWorkspace.path)
    }

    /// Triggers the remote project generation on GitHub: ensures the
    /// `build-project` branch exists, pushes all current project
    /// files to it, then pushes the generation workflow. The GitHub
    /// Actions workflow triggers automatically on the push to
    /// `build-project`.
    public func triggerRemoteGeneration(projectDir: URL, projectName: String, githubRepo: String?, workflowContent: String) async throws {
        guard let repoString = githubRepo else {
            throw BuilderError.notLinkedToGitHub
        }

        let (owner, repo) = try parseRepoURL(repoString)
        let branch = "build-project"

        // 1. Ensure the build-project branch exists
        do {
            try await githubClient.createBranch(owner: owner, repo: repo, branch: branch, from: "main")
        } catch {
            // Ignore error if branch already exists
            print("ProjectBuilderManager: Branch \(branch) might already exist or error: \(error.localizedDescription)")
        }

        // 2. Push all current files to the build-project branch
        try await pushProjectFiles(projectDir: projectDir, owner: owner, repo: repo, branch: branch, commitMessage: "Prepare project for remote generation")

        // 3. Push the workflow file to the branch
        let workflowPath = ".github/workflows/build-project.yml"
        let existingSHA = try? await githubClient.getFileSHA(owner: owner, repo: repo, path: workflowPath, ref: branch)
        _ = try await githubClient.pushFile(
            owner: owner,
            repo: repo,
            path: workflowPath,
            content: workflowContent,
            message: "Add remote generation workflow",
            sha: existingSHA,
            branch: branch
        )

        // The GHA workflow will be triggered automatically by the push to 'build-project' branch.
    }

    /// Pushes every file below `projectDir` (excluding `.git`,
    /// `.build`, and `DerivedData`) to `branch`, one Contents-API
    /// call per file (Legacy's `GitHubRepositoryManager.pushProject`,
    /// adapted from its `Project.files` tree to a directory walk).
    public func pushProjectFiles(projectDir: URL, owner: String, repo: String, branch: String, commitMessage: String) async throws {
        guard let enumerator = fm.enumerator(at: projectDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return
        }
        let skipped = Set([".git", ".build", "DerivedData", "Pods", "node_modules"])
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.pathComponents.contains(where: { skipped.contains($0) }) { continue }
            let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            guard isRegular else { continue }
            let relative = fileURL.path.replacingOccurrences(of: projectDir.standardizedFileURL.path + "/", with: "")
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let existingSHA = try? await githubClient.getFileSHA(owner: owner, repo: repo, path: relative, ref: branch)
            _ = try await githubClient.pushFile(
                owner: owner,
                repo: repo,
                path: relative,
                content: content,
                message: commitMessage,
                sha: existingSHA,
                branch: branch
            )
        }
    }

    /// Parses a GitHub repo URL (`https://github.com/owner/repo`,
    /// `git@github.com:owner/repo`, or `owner/repo`) into its owner
    /// and repo (Legacy `GitHubRepositoryManager.parseRepoURL`,
    /// verbatim).
    public func parseRepoURL(_ urlString: String) throws -> (owner: String, repo: String) {
        let cleaned = urlString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .replacingOccurrences(of: "git@github.com:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parts = cleaned.split(separator: "/", maxSplits: 2)
        guard parts.count >= 2 else {
            throw BuilderError.invalidRepoURL(urlString)
        }
        let owner = String(parts[0])
        let repo = String(parts[1]).replacingOccurrences(of: ".git", with: "")
        guard !owner.isEmpty, !repo.isEmpty else {
            throw BuilderError.invalidRepoURL(urlString)
        }
        return (owner, repo)
    }

    // MARK: - Generation

    private func ensureSubdirectories(in projectDir: URL) throws {
        for sub in ["Sources", "Views", "Features"] {
            let dir = projectDir.appendingPathComponent(sub)
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    private func ensureInfoPlist(at url: URL, bundleName: String) throws {
        guard !fm.fileExists(atPath: url.path) else { return }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>$(DEVELOPMENT_LANGUAGE)</string>
            <key>CFBundleExecutable</key>
            <string>$(EXECUTABLE_NAME)</string>
            <key>CFBundleIdentifier</key>
            <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>\(bundleName)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>UIApplicationSupportsIndirectInputEvents</key>
            <true/>
            <key>UISupportedInterfaceOrientations</key>
            <array>
                <string>UIInterfaceOrientationPortrait</string>
                <string>UIInterfaceOrientationLandscapeLeft</string>
                <string>UIInterfaceOrientationLandscapeRight</string>
            </array>
            <key>UISupportedInterfaceOrientations~ipad</key>
            <array>
                <string>UIInterfaceOrientationPortrait</string>
                <string>UIInterfaceOrientationPortraitUpsideDown</string>
                <string>UIInterfaceOrientationLandscapeLeft</string>
                <string>UIInterfaceOrientationLandscapeRight</string>
            </array>
        </dict>
        </plist>
        """

        try plist.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The XcodeGen spec for a user project (Legacy's
    /// `makeProjectYAML`, made public so the remote-generation UI
    /// and tests can render it without going through GitHub).
    public func makeProjectYAML(
        projectName: String,
        projectDir: URL,
        infoPlistURL: URL,
        swiftSourceFiles: [String]
    ) -> String {
        let sourceEntries = swiftSourceFiles.isEmpty
            ? ["Sources", "Views", "Features"]
            : swiftSourceFiles

        let sourceLines = sourceEntries.map { "      - \($0)" }.joined(separator: "\n")
        let plistRelative = relativePath(from: projectDir, to: infoPlistURL)
        let safeBundle = bundleIdentifierSuffix(for: projectName)

        return """
        name: \(projectName)

        options:
          bundleIdPrefix: com.swiftcode.userproject
          deploymentTarget:
            iOS: "16.0"

        settings:
          base:
            SWIFT_VERSION: 5.0
            IPHONEOS_DEPLOYMENT_TARGET: 16.0
            TARGETED_DEVICE_FAMILY: "1,2"

        configs:
          Debug: debug
          Release: release

        targets:
          \(projectName):
            type: application
            platform: iOS
            deploymentTarget: "16.0"
            sources:
        \(sourceLines)
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: com.swiftcode.userproject.\(safeBundle)
                INFOPLIST_FILE: \(plistRelative)
        """
    }

    /// Local xcodegen generation (Legacy's `runXcodeGen`): disabled
    /// by design — it throws when the spec is missing, and otherwise
    /// only runs when the `SWIFTCODE_RUN_XCODEGEN` env var is set,
    /// in which case it still throws, telling the caller to run
    /// `xcodegen generate --spec project.yml` manually. It never
    /// executes xcodegen itself.
    public func runXcodeGen(in projectRoot: URL) throws {
        let processInfo = ProcessInfo.processInfo
        let environment = processInfo.environment
        let arguments = processInfo.arguments
        let processID = processInfo.processIdentifier
        let systemUptime = processInfo.systemUptime

        let projectSpecURL = projectRoot.appendingPathComponent("project.yml")
        guard fm.fileExists(atPath: projectSpecURL.path) else {
            throw BuilderError.missingProjectSpec(projectSpecURL)
        }

        #if os(macOS)
        let platformDescription = "macOS"
        #elseif os(iOS)
        let platformDescription = "iOS"
        #else
        let platformDescription = "unsupported-platform"
        #endif

        let commandHint = "xcodegen generate --spec project.yml"
        let launchArguments = arguments.joined(separator: " ")
        let context = """
        platform=\(platformDescription)
        pid=\(processID)
        uptime=\(String(format: "%.2f", systemUptime))
        launchArguments=\(launchArguments)
        commandHint=\(commandHint)
        """

        if environment["SWIFTCODE_LOG_PROJECT_BUILDER_CONTEXT"] == "1" {
            print("ProjectBuilderManager context:\n\(context)")
        }

        if environment["SWIFTCODE_RUN_XCODEGEN"] == "1" {
            throw NSError(domain: "ProjectBuilderManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "External command execution is disabled. Run '\(commandHint)' manually in \(projectRoot.path).",
            ])
        }
    }

    // MARK: - File Collection

    public func collectSwiftFiles(in projectDir: URL) -> [String] {
        var allFiles: [String] = []
        for folder in ["Sources", "Views", "Features"] {
            let folderURL = projectDir.appendingPathComponent(folder)
            allFiles += collectSwiftFilesRecursively(in: folderURL, relativeTo: projectDir)
        }
        return allFiles.sorted()
    }

    private func collectSwiftFilesRecursively(in directory: URL, relativeTo base: URL) -> [String] {
        guard fm.fileExists(atPath: directory.path),
              let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
              )
        else { return [] }

        var results: [String] = []
        let basePath = base.standardizedFileURL.path

        for item in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDir {
                results += collectSwiftFilesRecursively(in: item, relativeTo: base)
            } else if item.pathExtension == "swift" {
                let fullPath = item.standardizedFileURL.path
                if fullPath.hasPrefix(basePath + "/") {
                    results.append(String(fullPath.dropFirst(basePath.count + 1)))
                }
            }
        }

        return results
    }

    private func bundleIdentifierSuffix(for projectName: String) -> String {
        let lowered = projectName.lowercased()
        let cleaned = lowered.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "-"
        }
        let collapsed = String(cleaned)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "app" : collapsed
    }

    private func relativePath(from base: URL, to target: URL) -> String {
        let baseComponents = base.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents

        var commonIndex = 0
        while commonIndex < min(baseComponents.count, targetComponents.count),
              baseComponents[commonIndex] == targetComponents[commonIndex] {
            commonIndex += 1
        }

        let upMoves = Array(repeating: "..", count: max(0, baseComponents.count - commonIndex))
        let downMoves = Array(targetComponents.dropFirst(commonIndex))
        let pathParts = upMoves + downMoves

        return pathParts.isEmpty ? "." : NSString.path(withComponents: pathParts)
    }
}
