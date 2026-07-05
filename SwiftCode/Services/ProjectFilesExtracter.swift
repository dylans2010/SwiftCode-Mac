import Foundation
import ZIPFoundation

/// Extracts generated project files from GitHub Actions artifacts and integrates them locally.
public final class ProjectFilesExtracter {
    public static let shared = ProjectFilesExtracter()
    private init() {}

    private let fm = FileManager.default

    /// Polls for the completion of a workflow run and downloads/integrates its artifacts.
    /// - Parameters:
    ///   - project: The local project to update.
    ///   - owner: GitHub repository owner.
    ///   - repo: GitHub repository name.
    ///   - branch: The branch the workflow was triggered on.
    ///   - progress: A closure called with progress updates (0.0 to 1.0) and status messages.
    ///   - logCallback: Optional closure to receive real-time logs.
    public func extractArtifacts(
        for project: Project,
        owner: String,
        repo: String,
        branch: String,
        progress: @escaping (Double, String) -> Void,
        logCallback: ((String) -> Void)? = nil
    ) async throws {
        progress(0.1, "Waiting for workflow to start...")

        // 1. Find the recent workflow run
        var run: WorkflowRun?
        for _ in 0..<12 { // Wait up to 1 minute for run to appear
            let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
            run = runs.first { $0.headBranch == branch && $0.status != "completed" }
            if run != nil { break }
            try await Task.sleep(for: .seconds(5))
        }

        guard let activeRun = run else {
            // Check if it already completed quickly
            let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
            if let completedRun = runs.first(where: { $0.headBranch == branch }) {
                run = completedRun
            } else {
                throw NSError(domain: "ProjectFilesExtracter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workflow run not found."])
            }
            return
        }

        // 2. Poll for completion and fetch logs
        progress(0.2, "Processing with GitHub Actions...")
        var currentRun = activeRun
        var _: Int?

        while currentRun.isRunning {
            try await Task.sleep(for: .seconds(5))

            // Update run status
            currentRun = try await GitHubService.shared.getWorkflowRun(owner: owner, repo: repo, runID: currentRun.id)
            progress(0.4, "Workflow status: \(currentRun.status.capitalized)...")

            // Try to fetch logs
            do {
                let jobs = try await GitHubService.shared.listWorkflowJobs(owner: owner, repo: repo, runID: currentRun.id)
                if let firstJob = jobs.first {
                    let logs = try await GitHubService.shared.getJobLogs(owner: owner, repo: repo, jobID: firstJob.id)
                    logCallback?(logs)
                }
            } catch {
                // Ignore log fetching errors to keep the process running
                print("Failed to fetch logs: \(error.localizedDescription)")
            }
        }

        guard currentRun.conclusion == "success" else {
            throw NSError(domain: "ProjectFilesExtracter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Workflow failed with conclusion: \(currentRun.conclusion ?? "unknown")"])
        }

        // 3. Find and download artifact
        progress(0.6, "Downloading CI artifacts...")
        let artifacts = try await GitHubService.shared.listWorkflowArtifacts(owner: owner, repo: repo, runID: currentRun.id)
        guard let projectArtifact = artifacts.first(where: { $0.name == "generated-xcode-files" }) else {
            throw NSError(domain: "ProjectFilesExtracter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Artifact 'generated-xcode-files' not found."])
        }

        var zipData: Data?
        var lastError: Error?
        for attempt in 1...3 {
            do {
                zipData = try await GitHubService.shared.downloadArtifact(owner: owner, repo: repo, artifactID: projectArtifact.id)
                if zipData != nil { break }
            } catch {
                lastError = error
                if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
            }
        }

        guard let finalZipData = zipData else {
            throw lastError ?? NSError(domain: "ProjectFilesExtracter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to download artifacts after 3 retries."])
        }

        // 4. Integrate into local project
        progress(0.8, "Extracting Files...")
        try await integrate(zipData: finalZipData, into: project, progress: progress)

        progress(1.0, "Required files have been added successfully to the directory!")
    }

    private func integrate(zipData: Data, into project: Project, progress: @escaping (Double, String) -> Void) async throws {
        let tempBase = fm.temporaryDirectory.appendingPathComponent("SwiftCode/Backend/tmp/", isDirectory: true)
        let tempDir = tempBase.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let zipURL = tempDir.appendingPathComponent("artifacts.zip")
        try zipData.write(to: zipURL)

        let extractionDir = tempDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractionDir, withIntermediateDirectories: true)

        // Use ZIPFoundation's unzipItem, which is compatible with iOS
        try fm.unzipItem(at: zipURL, to: extractionDir)

        progress(0.9, "Adding Files to App’s Directory...")

        let projectDir = await project.directoryURL
        let items = try fm.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)

        let projectName = project.name
        let forbiddenFiles = ["build-project.yml", "project.yml"]

        for item in items {
            var filename = item.lastPathComponent
            if forbiddenFiles.contains(filename) { continue }

            // Support both generic and specific naming from artifact
            if filename == "GeneratedProject.xcodeproj" {
                filename = "\(projectName).xcodeproj"
            } else if filename == "GeneratedProject.xcworkspace" {
                filename = "\(projectName).xcworkspace"
            }

            let destURL = projectDir.appendingPathComponent(filename)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: item, to: destURL)
        }

        // Integrity check: verify that essential files are present
        let xcodeProj = projectDir.appendingPathComponent("\(projectName).xcodeproj")
        let xcworkspace = projectDir.appendingPathComponent("\(projectName).xcworkspace")

        guard fm.fileExists(atPath: xcodeProj.path) && fm.fileExists(atPath: xcworkspace.path) else {
            throw NSError(domain: "ProjectFilesExtracter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Integrity check failed: \(projectName).xcodeproj or .xcworkspace missing after extraction."])
        }

        // Refresh the file tree
        await MainActor.run {
            ProjectManager.shared.refreshFileTree(for: project)
        }
    }
}
