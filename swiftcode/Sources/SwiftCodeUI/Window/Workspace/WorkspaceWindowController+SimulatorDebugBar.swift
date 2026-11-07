import AppKit
import SwiftCodeSimFeatures

extension WorkspaceWindowController {
    func wireSimulatorDebugBar() {
        debugArea.simulatorRunKey = { [weak self] in
            guard let r = self?.session.simulatorRun, case .remote = r.target, r.exitStatus == nil, r.remote != nil else { return nil }
            return "\(r.app.bundleID)#\(r.remotePID ?? 0)"
        }
        debugArea.applyEnvironmentOverrides = { [weak self] overrides in
            guard let self, let r = self.session.simulatorRun, case .remote = r.target, let remote = r.remote else {
                return (false, "No app is running on the SwiftCode simulator.")
            }
            return await self.session.controlRemoteSimulator(remote: remote, overrides.commandWords(bundleID: r.app.bundleID))
        }
        debugArea.simulateLocationHandler = { [weak self] words in
            guard let self, let r = self.session.simulatorRun, case .remote = r.target, let remote = r.remote else {
                return (false, "No app is running on the SwiftCode simulator.")
            }
            return await self.session.controlRemoteSimulator(remote: remote, ["location"] + words)
        }
    }
}
