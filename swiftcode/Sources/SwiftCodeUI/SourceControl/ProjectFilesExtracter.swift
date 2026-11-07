import Foundation
import SwiftCodeAssistant
import SwiftCodeGitHub
import SwiftCodeIDECore

public final class ProjectFilesExtracter: Sendable {
    public static let shared = ProjectFilesExtracter()
    private init() {}

    private var gitHubClient: GitHubClient {
        let store = defaultSecretStore()
        return GitHubClient(tokenProvider: { store.readString(SecretAccount.githubToken) })
    }

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

    public func extractArtifacts(
        for project: Project,
        owner: String,
        repo: String,
        branch: String,
        progress: @escaping (Double, String) -> Void,
        logCallback: ((String) -> Void)? = nil
    ) async throws {
        progress(0.1, "Waiting for workflow to start...")

        var run: GitHubWorkflowRun?
        for _ in 0..<12 {
            let runs = try await gitHubClient.listWorkflowRuns(owner: owner, repo: repo)
            run = runs.first { $0.headBranch == branch && $0.status != "completed" }
            if run != nil { break }
            try await Task.sleep(for: .seconds(5))
        }

        guard let activeRun = run else {
            let runs = try await gitHubClient.listWorkflowRuns(owner: owner, repo: repo)
            if let completedRun = runs.first(where: { $0.headBranch == branch }) {
                run = completedRun
            } else {
                throw NSError(domain: "ProjectFilesExtracter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Workflow run not found."])
            }
            return
        }

        progress(0.2, "Processing with GitHub Actions...")
        var currentRun = activeRun
        var _: Int?

        while currentRun.isRunning {
            try await Task.sleep(for: .seconds(5))

            currentRun = try await gitHubClient.getWorkflowRun(owner: owner, repo: repo, runID: currentRun.id)
            progress(0.4, "Workflow status: \(currentRun.status.capitalized)...")

            do {
                let jobs = try await gitHubClient.listWorkflowJobs(owner: owner, repo: repo, runID: currentRun.id)
                if let firstJob = jobs.first {
                    let logs = try await gitHubClient.getJobLogs(owner: owner, repo: repo, jobID: firstJob.id)
                    logCallback?(logs)
                }
            } catch {
                print("Failed to fetch logs: \(error.localizedDescription)")
            }
        }

        guard currentRun.conclusion == "success" else {
            throw NSError(domain: "ProjectFilesExtracter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Workflow failed with conclusion: \(currentRun.conclusion ?? "unknown")"])
        }

        progress(0.6, "Downloading CI artifacts...")
        let artifacts = try await gitHubClient.listWorkflowArtifacts(owner: owner, repo: repo, runID: currentRun.id)
        guard let projectArtifact = artifacts.first(where: { $0.name == "generated-xcode-files" }) else {
            throw NSError(domain: "ProjectFilesExtracter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Artifact 'generated-xcode-files' not found."])
        }

        var zipData: Data?
        var lastError: Error?
        for attempt in 1...3 {
            do {
                zipData = try await gitHubClient.downloadArtifact(owner: owner, repo: repo, artifactID: projectArtifact.id)
                if zipData != nil { break }
            } catch {
                lastError = error
                if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
            }
        }

        guard let finalZipData = zipData else {
            throw lastError ?? NSError(domain: "ProjectFilesExtracter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to download artifacts after 3 retries."])
        }

        progress(0.8, "Extracting Files...")
        try await integrate(zipData: finalZipData, into: project, progress: progress)

        progress(1.0, "Required files have been added successfully to the directory!")
    }

    private func integrate(zipData: Data, into project: Project, progress: @escaping (Double, String) -> Void) async throws {
        let fm = FileManager.default
        let tempBase = fm.temporaryDirectory.appendingPathComponent("SwiftCode/Backend/tmp/", isDirectory: true)
        let tempDir = tempBase.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let zipURL = tempDir.appendingPathComponent("artifacts.zip")
        try zipData.write(to: zipURL)

        let extractionDir = tempDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extractionDir, withIntermediateDirectories: true)

        try unzip(zipURL, to: extractionDir)

        progress(0.9, "Adding Files to App’s Directory...")

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

            let destURL = projectDir.appendingPathComponent(filename)
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.moveItem(at: item, to: destURL)
        }

        let xcodeProj = projectDir.appendingPathComponent("\(projectName).xcodeproj")
        let xcworkspace = projectDir.appendingPathComponent("\(projectName).xcworkspace")

        guard fm.fileExists(atPath: xcodeProj.path) && fm.fileExists(atPath: xcworkspace.path) else {
            throw NSError(domain: "ProjectFilesExtracter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Integrity check failed: \(projectName).xcodeproj or .xcworkspace missing after extraction."])
        }

        await MainActor.run {
            ProjectSessionStore.shared.refreshFileTree(for: project)
        }
    }
}
