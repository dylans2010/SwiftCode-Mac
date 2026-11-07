import Foundation
import Observation

@Observable
@MainActor
public final class LocalBuildService {
    public var buildLogs: [BuildStatusMessage] = []
    public var isBuilding = false
    public var progress: Double = 0.0

    private var session: URLSession

    public init() {
        self.session = URLSession(configuration: .default)
    }

    public func startBuild(on mac: DiscoveredMac, projectURL: URL, projectName: String) async throws -> URL? {
        isBuilding = true
        buildLogs = []
        progress = 0.0
        defer { isBuilding = false }

        addLog("Connecting to \(mac.name)...")

        addLog("Packaging project files...")
        let projectData = try await Task.detached {
            try await ProjectPackager.shared.packageProject(at: projectURL)
        }.value

        addLog("Sending project to \(mac.host)...")
        updateProgress(0.2)

        let buildRequest = BuildRequest(
            projectName: projectName,
            projectData: projectData
        )

        let url = URL(string: "http://\(mac.host):\(mac.port)/build")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(buildRequest)

        addLog("Building app on \(mac.name) with Xcode...")
        updateProgress(0.5)
        let (data, urlResponse) = try await session.data(for: request)
        guard let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (urlResponse as? HTTPURLResponse)?.statusCode ?? -1
            addLog("Build failed: remote build server returned HTTP \(code)")
            return nil
        }
        let response = try JSONDecoder().decode(BuildResponse.self, from: data)

        if response.success, let ipaData = response.ipaData {
            addLog("Receiving IPA...")
            updateProgress(0.8)
            let savedURL = try ProjectPackager.shared.saveIPA(data: ipaData, projectName: projectName)

            addLog("Build completed successfully")
            updateProgress(1.0)
            return savedURL
        } else {
            addLog("Build failed: \(response.message)")
            return nil
        }
    }

    private func addLog(_ message: String) {
        buildLogs.append(BuildStatusMessage(status: message))
    }

    private func updateProgress(_ value: Double) {
        progress = value
    }
}
