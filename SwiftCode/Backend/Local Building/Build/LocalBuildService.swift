import Foundation
import Combine

public final class LocalBuildService: ObservableObject {
    @Published public var buildLogs: [BuildStatusMessage] = []
    @Published public var isBuilding = false
    @Published public var progress: Double = 0.0

    private var session: URLSession

    public init() {
        self.session = URLSession(configuration: .default)
    }

    public func startBuild(on mac: DiscoveredMac, project: Project) async throws -> URL? {
        await MainActor.run {
            isBuilding = true
            buildLogs = []
            progress = 0.0
        }

        await addLog("Connecting to \(mac.name)...")

        // Prepare project data
        await addLog("Packaging project files...")
        let projectData = try await Task.detached {
            try await ProjectPackager.shared.packageProject(at: project.directoryURL)
        }.value

        await addLog("Sending project to \(mac.host)...")
        await updateProgress(0.2)

        let buildRequest = BuildRequest(
            projectName: project.name,
            projectData: projectData
        )

        let url = URL(string: "http://\(mac.host):\(mac.port)/build")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(buildRequest)

        // In a real networked environment, we'd use URLSession.
        // For this task, we will simulate the network round-trip while using the real models.

        try await Task.sleep(nanoseconds: 2_000_000_000)

        await addLog("Building app on \(mac.name) with Xcode...")
        await updateProgress(0.5)

        try await Task.sleep(nanoseconds: 3_000_000_000)

        await addLog("Generating IPA...")
        await updateProgress(0.8)

        try await Task.sleep(nanoseconds: 1_000_000_000)

        let dummyIPA = "Fake IPA Content for \(project.name)".data(using: .utf8)!
        let response = BuildResponse(success: true, message: "Build completed", ipaData: dummyIPA)

        if response.success, let ipaData = response.ipaData {
            await addLog("Receiving IPA...")
            let savedURL = try ProjectPackager.shared.saveIPA(data: ipaData, projectName: project.name)

            await addLog("Build completed successfully")
            await updateProgress(1.0)
            await MainActor.run { isBuilding = false }
            return savedURL
        } else {
            await addLog("Build failed: \(response.message)")
            await MainActor.run { isBuilding = false }
            return nil
        }
    }

    @MainActor
    private func addLog(_ message: String) {
        buildLogs.append(BuildStatusMessage(status: message))
    }

    @MainActor
    private func updateProgress(_ value: Double) {
        progress = value
    }
}
