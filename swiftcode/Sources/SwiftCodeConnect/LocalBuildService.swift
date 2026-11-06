// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Local Building/Build/LocalBuildService.swift
// Adapted for SwiftCode — honestly. Legacy built the real URLRequest, then slept
// 2s/3s/1s and returned "Fake IPA Content for <name>" as the IPA ("In a real
// networked environment, we'd use URLSession... we will simulate"). The fake
// is NOT ported: this version performs the real URLSession POST to
// http://<mac.host>:<port>/build with the BuildRequest, decodes the
// BuildResponse, and saves the IPA via ProjectPackager on success. The
// `Project` parameter became an explicit project URL + name (SwiftCode has no
// Legacy `Project` model); the log/progress reporting is unchanged.

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

    /// Builds `projectName` (at `projectURL`) on the discovered Mac and
    /// returns the saved IPA URL, or nil when the remote build fails.
    /// Throws for packaging / transport errors.
    public func startBuild(on mac: DiscoveredMac, projectURL: URL, projectName: String) async throws -> URL? {
        isBuilding = true
        buildLogs = []
        progress = 0.0
        defer { isBuilding = false }

        addLog("Connecting to \(mac.name)...")

        // Prepare project data
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
