import Foundation
import ZIPFoundation

/// Coordinates retrieval of generated build assets from GitHub Actions and integrates them in the user's project.
public final class BuildingSystemAPI {
    public static let shared = BuildingSystemAPI()
    private init() {}

    private let fm = FileManager.default

    public func fetchAndIntegrateGeneratedFiles(
        for project: Project,
        owner: String,
        repo: String,
        branch: String,
        progress: @escaping (Double, String) -> Void,
        logCallback: ((String) -> Void)? = nil
    ) async throws {
        progress(0.1, "Waiting for workflow to start...")

        var run: WorkflowRun?
        for _ in 0..<12 {
            let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
            run = runs.first { $0.headBranch == branch && $0.status != "completed" }
            if run != nil { break }
            try await Task.sleep(for: .seconds(5))
        }

        if run == nil {
            let runs = try await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repo)
            run = runs.first(where: { $0.headBranch == branch })
        }

        guard var currentRun = run else {
            throw NSError(domain: "BuildingSystemAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workflow run not found."])
        }

        progress(0.25, "Processing with GitHub Actions...")
        while currentRun.isRunning {
            try await Task.sleep(for: .seconds(5))
            currentRun = try await GitHubService.shared.getWorkflowRun(owner: owner, repo: repo, runID: currentRun.id)
            progress(0.45, "Workflow status: \(currentRun.status.capitalized)...")

            do {
                let jobs = try await GitHubService.shared.listWorkflowJobs(owner: owner, repo: repo, runID: currentRun.id)
                if let firstJob = jobs.first {
                    let logs = try await GitHubService.shared.getJobLogs(owner: owner, repo: repo, jobID: firstJob.id)
                    logCallback?(logs)
                }
            } catch {
                // Keep polling even if logs fail intermittently.
            }
        }

        guard currentRun.conclusion == "success" else {
            throw NSError(domain: "BuildingSystemAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Workflow failed with conclusion: \(currentRun.conclusion ?? "unknown")"])
        }

        progress(0.65, "Downloading generated-xcode-files.zip...")
        let artifacts = try await GitHubService.shared.listWorkflowArtifacts(owner: owner, repo: repo, runID: currentRun.id)
        guard let projectArtifact = artifacts.first(where: { $0.name == "generated-xcode-files" }) else {
            throw NSError(domain: "BuildingSystemAPI", code: 3, userInfo: [NSLocalizedDescriptionKey: "Artifact 'generated-xcode-files' not found."])
        }

        let zipData = try await downloadArtifactData(owner: owner, repo: repo, artifactID: projectArtifact.id)
        progress(0.8, "Extracting generated-xcode-files.zip...")
        try await integrateGeneratedZip(zipData: zipData, into: project, progress: progress)

        progress(1.0, "Required files have been added successfully to the directory!")
    }

    private func downloadArtifactData(owner: String, repo: String, artifactID: Int) async throws -> Data {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try await GitHubService.shared.downloadArtifact(owner: owner, repo: repo, artifactID: artifactID)
            } catch {
                lastError = error
                if attempt < 3 {
                    try await Task.sleep(for: .seconds(2))
                }
            }
        }

        throw lastError ?? NSError(domain: "BuildingSystemAPI", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to download generated-xcode-files.zip after 3 retries."])
    }

    private func integrateGeneratedZip(
        zipData: Data,
        into project: Project,
        progress: @escaping (Double, String) -> Void
    ) async throws {
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("BuildingSystemAPI", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let artifactZipURL = tempDir.appendingPathComponent("generated-xcode-files.zip")
        try zipData.write(to: artifactZipURL)

        let extractionDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        try fm.unzipItem(at: artifactZipURL, to: extractionDir)

        progress(0.9, "Adding files to project directory...")
        let projectDir = await project.directoryURL
        let items = try fm.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)

        let projectName = project.name
        let forbiddenFiles = ["build-project.yml", "project.yml"]

        for item in items {
            var filename = item.lastPathComponent
            if forbiddenFiles.contains(filename) { continue }

            if filename == "GeneratedProject.xcodeproj" {
                filename = "\(projectName).xcodeproj"
            } else if filename == "GeneratedProject.xcworkspace" {
                filename = "\(projectName).xcworkspace"
            }

            let destination = projectDir.appendingPathComponent(filename)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: item, to: destination)
        }

        let xcodeProj = projectDir.appendingPathComponent("\(projectName).xcodeproj")
        let xcworkspace = projectDir.appendingPathComponent("\(projectName).xcworkspace")

        guard fm.fileExists(atPath: xcodeProj.path), fm.fileExists(atPath: xcworkspace.path) else {
            throw NSError(domain: "BuildingSystemAPI", code: 5, userInfo: [NSLocalizedDescriptionKey: "Integrity check failed: \(projectName).xcodeproj or \(projectName).xcworkspace missing after extraction."])
        }

        await MainActor.run {
            ProjectManager.shared.refreshFileTree(for: project)
        }
    }
}
