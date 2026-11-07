import Foundation

extension DeviceLayout {
    static let pairingAgentLabel = "dev.swiftcode.simulator.pairing"
    var pairingAgentHostPath: String { data + "/Library/SwiftCode/bin/swiftcode-pairing-agent" }
    var pairingAgentPlistPath: String { data + "/Library/LaunchDaemons/\(Self.pairingAgentLabel).plist" }
    var pairingAgentLogPath: String { data + "/tmp/swiftcode-pairing-agent.log" }
    var pairingAgentStatePath: String { data + "/tmp/swiftcode-pairing-agent.state" }

    var pairingAgentPlist: [String: Any] {
        ["Label": Self.pairingAgentLabel,
         "ProgramArguments": [guestPath(pairingAgentHostPath)],
         "RootedSimulatorPath": true,
         "ProcessType": "Interactive",
         "RunAtLoad": true,
         "KeepAlive": true,
         "StandardErrorPath": guestPath(pairingAgentLogPath),
         "EnvironmentVariables": ["SWIFTCODE_PAIRING_AGENT": "1",
                                  "SWIFTCODE_PAIRING_AGENT_STATE": guestPath(pairingAgentStatePath)]]
    }

    func stagePairingAgent() throws {
        let fm = FileManager.default
        guard let agent = pairingAgent, fm.fileExists(atPath: agent), try stageImage(agent, to: pairingAgentHostPath, mode: 0o755) else {
            if fm.fileExists(atPath: pairingAgentPlistPath) { try fm.removeItem(atPath: pairingAgentPlistPath) }
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: pairingAgentPlist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: pairingAgentPlistPath), options: .atomic)
        for path in [pairingAgentLogPath, pairingAgentStatePath] where fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }
}
