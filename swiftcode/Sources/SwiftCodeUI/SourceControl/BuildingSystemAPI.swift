// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/GitHub/BuildingSystemAPI.swift
//
// Adapted for SwiftCode: `GitHubService` / `WorkflowRun` do not exist
// here — the calls go to `GitHubClient` (`SwiftCodeGitHub`) with the
// `GitHubWorkflowRun` / `GitHubWorkflowJob` / `GitHubArtifact` models,
// and `Project` / `ProjectSessionStore` come from `SwiftCodeIDECore`.
// `import ZIPFoundation` is dropped (not a SwiftCode dependency);
// extraction uses ditto/unzip (see `unzip(_:to:)` below).
// Behaviour (polling, retry, forbidden files, rename, integrity check)
// is unchanged. Called from `PrepareCompileWaitingView`.
// See DISPOSITIONS.md for the remaining wiring note.

import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore


/// Coordinates retrieval of generated build assets from GitHub Actions and integrates them in the user's project.
public final class BuildingSystemAPI: @unchecked Sendable {
    public static let shared = BuildingSystemAPI()
    private init() {}

    private let fm = FileManager.default

    /// The GitHub API client, authenticated with the stored GitHub token
    /// (same `defaultSecretStore()` pattern as `GitHubImporter`).
    private var gitHubClient: GitHubClient {
        let store = defaultSecretStore()
        return GitHubClient(tokenProvider: { store.readString(SecretAccount.githubToken) })
    }

    /// Extract a zip without ZIPFoundation (not a SwiftCode dependency):
    /// `/usr/bin/ditto -x -k` on macOS, `/usr/bin/unzip` elsewhere — the
    /// same approach `ProjectZipImporter` uses.
    private func unzip(_ zipURL: URL, to destination: URL) throws {
        let process = Process()
        #if os(macOS)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, destination.path]
        #else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw NSError(domain: "ZipExtraction", code: 1, userInfo: [NSLocalizedDescriptionKey: "unzip is not available on this system."])
        }
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipURL.path, "-d", destination.path]
        #endif
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ZipExtraction", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to extract \(zipURL.lastPathComponent)."])
        }
    }

    public func fetchAndIntegrateGeneratedFiles(
        for project: Project,
        owner: String,
        repo: String,
        branch: String,
        progress: @Sendable @escaping (Double, String) -> Void,
        logCallback: (@Sendable (String) -> Void)? = nil
    ) async throws {
        progress(0.1, "Waiting for workflow to start...")

        var run: GitHubWorkflowRun?
        for _ in 0..<12 {
            let runs = try await gitHubClient.listWorkflowRuns(owner: owner, repo: repo)
            run = runs.first { $0.headBranch == branch && $0.status != "completed" }
            if run != nil { break }
            try await Task.sleep(for: .seconds(5))
        }

        if run == nil {
            let runs = try await gitHubClient.listWorkflowRuns(owner: owner, repo: repo)
            run = runs.first(where: { $0.headBranch == branch })
        }

        guard var currentRun = run else {
            throw NSError(domain: "BuildingSystemAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workflow run not found."])
        }

        progress(0.25, "Processing with GitHub Actions...")
        while currentRun.isRunning {
            try await Task.sleep(for: .seconds(5))
            currentRun = try await gitHubClient.getWorkflowRun(owner: owner, repo: repo, runID: currentRun.id)
            progress(0.45, "Workflow status: \(currentRun.status.capitalized)...")

            do {
                let jobs = try await gitHubClient.listWorkflowJobs(owner: owner, repo: repo, runID: currentRun.id)
                if let firstJob = jobs.first {
                    let logs = try await gitHubClient.getJobLogs(owner: owner, repo: repo, jobID: firstJob.id)
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
        let artifacts = try await gitHubClient.listWorkflowArtifacts(owner: owner, repo: repo, runID: currentRun.id)
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
                return try await gitHubClient.downloadArtifact(owner: owner, repo: repo, artifactID: artifactID)
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
        progress: @Sendable @escaping (Double, String) -> Void
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
        try unzip(artifactZipURL, to: extractionDir)

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
            ProjectSessionStore.shared.refreshFileTree(for: project)
        }
    }
}
