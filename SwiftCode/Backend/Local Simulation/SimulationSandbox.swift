import Foundation

struct SimulationSandboxPolicy {
    let projectDirectory: URL
    let allowNetwork: Bool
    let blockedPaths: [String]
}

final class SimulationSandbox {
    func makePolicy(projectDirectory: URL, allowNetwork: Bool = false) -> SimulationSandboxPolicy {
        SimulationSandboxPolicy(
            projectDirectory: projectDirectory,
            allowNetwork: allowNetwork,
            blockedPaths: ["/System", "/private", "/var"]
        )
    }
}
