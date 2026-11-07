import Foundation
import YcodeHealthStore
import YcodeSimFeatures

extension DeviceLayout {
    static let healthAgentLabel = "dev.swiftcode.simulator.health"
    static let healthAgentBundleName = "SwiftCodeHealth.app"
    var healthAgentHostPath: String { data + "/Library/SwiftCode/" + Self.healthAgentBundleName }
    var healthAgentExecutableHostPath: String { healthAgentHostPath + "/SwiftCodeHealth" }
    var healthAgentPlistPath: String { data + "/Library/LaunchDaemons/\(Self.healthAgentLabel).plist" }
    var healthAgentLogPath: String { data + "/tmp/swiftcode-health-agent.log" }
    var healthPendingPath: String { HealthDeviceFiles(dev: dev).pendingPath }
    var healthBackupsPath: String { HealthDeviceFiles(dev: dev).backupsPath }

    var healthAgentPlist: [String: Any] {
        ["Label": Self.healthAgentLabel,
         "ProgramArguments": [guestPath(healthAgentExecutableHostPath)],
         "RootedSimulatorPath": true,
         "ProcessType": "Interactive",
         "RunAtLoad": true,
         "KeepAlive": true,
         "StandardErrorPath": guestPath(healthAgentLogPath),
         "EnvironmentVariables": ["SWIFTCODE_HEALTH_AGENT": "1"]]
    }

    func healthAgentBuild(_ source: String) -> String? {
        switch runtimePlatform() {
        case .iOS: return source
        case .watchOS: return platformBuild(of: source)
        case .visionOS: return nil
        }
    }

    func stageHealthAgent() throws {
        let fm = FileManager.default
        guard let agent = healthAgent, fm.fileExists(atPath: agent + "/SwiftCodeHealth"), let build = healthAgentBuild(agent) else {
            if fm.fileExists(atPath: healthAgentPlistPath) { try fm.removeItem(atPath: healthAgentPlistPath) }
            return
        }
        try fm.createDirectory(atPath: (healthAgentHostPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: healthAgentHostPath) { try fm.removeItem(atPath: healthAgentHostPath) }
        try fm.copyItem(atPath: build, toPath: healthAgentHostPath)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: healthAgentExecutableHostPath)
        let data = try PropertyListSerialization.data(fromPropertyList: healthAgentPlist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: healthAgentPlistPath), options: .atomic)
        if fm.fileExists(atPath: healthAgentLogPath) { try? fm.removeItem(atPath: healthAgentLogPath) }
        HealthDeviceFiles(dev: dev).applyShutDownEdits(log: { FileHandle.standardError.write(Data(("swiftcode-simd: health: " + $0 + "\n").utf8)) })
    }
}

struct HealthDeviceFiles {
    let dev: String
    var store: HealthStore { HealthStore(dev: dev) }
    var pendingPath: String { dev + "/swiftcode-pending-health.txt" }
    var backupsPath: String { dev + "/swiftcode-health-backups" }

    func pending() -> [String] {
        ((try? String(contentsOfFile: pendingPath, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline).map(String.init)
            .filter { !$0.isEmpty }
    }

    func setPending(_ lines: [String]) {
        if lines.isEmpty {
            try? FileManager.default.removeItem(atPath: pendingPath)
        } else {
            try? (lines.joined(separator: "\n") + "\n").write(toFile: pendingPath, atomically: true, encoding: .utf8)
        }
    }

    func queue(_ verb: String, _ bundleID: String) {
        setPending(pending().filter { !$0.hasSuffix(" " + bundleID) } + ["\(verb) \(bundleID)"])
    }

    @discardableResult
    func applyShutDownEdits(log: (String) -> Void) -> [String] {
        let s = store
        guard s.exists else {
            log("no health store yet (first boot); the agent asks for access in this boot and is granted at the next cold boot")
            return []
        }
        var lines: [String] = []
        var still: [String] = []
        let queued = pending()
        let agentRows = (try? s.authorizationRows(bundleID: HealthChannel.agentBundleID)) ?? []
        let agentNeeds = agentRows.contains { $0.request == HealthAuthorizationCode.sharePresented && $0.status != HealthAuthorizationCode.sharingAuthorized }
        guard agentNeeds || !queued.isEmpty else {
            log(agentRows.isEmpty ? "the agent has not asked for access yet (it asks in this boot; granted at the next cold boot)"
                : "the agent's \(agentRows.count) grants are in place")
            return []
        }
        do {
            let backup = try s.backup(into: backupsPath, reason: "grants")
            lines.append("store backed up to \(backup)")
        } catch {
            log("no edits: the store's backup failed: \(error)")
            return []
        }
        if agentNeeds {
            do { lines.append("agent \(HealthChannel.agentBundleID): \(try s.grant(bundleID: HealthChannel.agentBundleID))") } catch {
                lines.append("agent grant failed: \(error)")
            }
        }
        for line in queued {
            let w = line.split(separator: " ").map(String.init)
            guard w.count == 2 else { continue }
            do {
                let r = w[0] == "revoke" ? try s.revoke(bundleID: w[1]) : try s.grant(bundleID: w[1])
                lines.append("\(w[0]) \(w[1]): \(r)")
                if r.rows == 0 { still.append(line) }
            } catch {
                lines.append("\(w[0]) \(w[1]) failed: \(error)")
                still.append(line)
            }
        }
        setPending(still)
        for l in lines { log(l) }
        return lines
    }
}
