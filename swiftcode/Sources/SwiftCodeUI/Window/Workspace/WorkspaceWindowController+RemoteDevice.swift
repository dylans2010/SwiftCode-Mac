import AppKit
import SwiftCodeIDECore

extension WorkspaceWindowController {
    static var remoteSimulatorInUse: Bool {
        NSApp?.windows.contains { w in
            guard let wc = w.windowController as? WorkspaceWindowController, case .remote = wc.session.simulatorRun?.target else { return false }
            return true
        } ?? false
    }

    func configureSwiftCodeRemoteDevice(_ c: DevicesController, defaults: UserDefaults = Preferences.shared.defaults, ssh: String? = nil) {
        let settings = RemoteSimulatorSettings.load(defaults)
        guard settings.isConfigured else { return }
        let busy: (RemoteSimulator) -> Bool = { [weak self] remote in
            if let r = self?.session.simulatorRun, case .remote = r.target {
                return r.remote?.remoteDevicePath == nil || r.remote?.remoteDevicePath == remote.remoteDevicePath
            }
            return Self.remoteSimulatorInUse
        }
        let running: (RemoteSimulator) -> Bool = { busy($0) || RemoteDeviceSessions.shared.isRunning($0) }
        c.setSwiftCodeRemote(rows: RemoteSimulator.hub(settings).map { DeviceRow.swiftcodeRemote($0, running: running($0)) })
        c.currentRemoteRows = {
            RemoteSimulator.hub(RemoteSimulatorSettings.load(defaults)).map { DeviceRow.swiftcodeRemote($0, running: running($0)) }
        }
        let remoteFor: (DeviceRow) -> RemoteSimulator? = { row in
            var settings = RemoteSimulatorSettings.load(defaults)
            if let ssh { settings.ssh = ssh }
            return RemoteSimulator.hub(settings).first { "\(settings.destination):\($0.remoteDevicePath)" == row.identifier }
        }
        c.startDevice = { [weak self] row in
            guard let remote = remoteFor(row) else { return (false, "Set the remote simulator in Settings ▸ Simulators first.") }
            if busy(remote) { return (false, "\(row.name) is running an app.") }
            RemoteDeviceSessions.shared.output = { [weak self] line in self?.session.appendConsole(line + "\n", kind: .debugger) }
            self?.session.appendConsole("SwiftCode: starting \(row.name) on \(remote.settings.destination)\n", kind: .debugger)
            return RemoteDeviceSessions.shared.start(remote) ? (true, "Started") : (false, "\(row.name) could not be started.")
        }
        c.shutDownDevice = { [weak self] row, force in
            guard let remote = remoteFor(row) else { return (false, "Set the remote simulator in Settings ▸ Simulators first.") }
            if RemoteDeviceSessions.shared.isRunning(remote) {
                await RemoteDeviceSessions.shared.shutDown(remote, force: force)
                return (true, "Shut down")
            }
            if let self, let run = self.session.simulatorRun, case .remote = run.target, run.remote?.remoteDevicePath == remote.remoteDevicePath {
                self.session.stopSimulatorRun(remote: remote)
                return (true, "Stopping the run")
            }
            return (false, "\(row.name) is used by another window's run; stop it there.")
        }
        c.makeDisplayLink = { row in
            guard let remote = remoteFor(row) else { return nil }
            return RemoteDisplayLink(remote: remote, name: remote.target?.deviceType.name ?? row.name, os: "\(row.platform) \(row.osVersion)")
        }
        c.headset.visionDisplay = (get: { RemoteSimulatorSettings.load(defaults).visionDisplay },
                                   set: { v in var s = RemoteSimulatorSettings.load(defaults); s.visionDisplay = v; s.save(defaults) })
        c.headset.route = { [weak c] row in
            guard let remote = remoteFor(row) else { return nil }
            let fromViewer = c?.headsetSettings.simulatorHostFromViewer ?? ""
            return .sshSocket(destination: fromViewer.isEmpty ? remote.settings.destination : fromViewer, socket: remote.displaySocketPath)
        }
        c.cameraSetting = DevicesController.cameraSetting(defaults)
        configureRemotePairing(c, defaults: defaults, ssh: ssh)
        c.eraseDevice = { [weak self, weak c] row in
            guard let self else { return (false, "The workspace was closed.") }
            if Self.remoteSimulatorInUse { return (false, "Stop the run on \(RemoteSimulator.deviceName) before erasing it.") }
            var settings = RemoteSimulatorSettings.load(defaults)
            if let ssh { settings.ssh = ssh }
            let all = RemoteSimulator.hub(settings)
            guard let remote = all.first(where: { "\(settings.destination):\($0.remoteDevicePath)" == row.identifier }) ?? all.first else {
                return (false, "Set the remote simulator in Settings ▸ Simulators first.")
            }
            let result = await self.session.eraseRemoteSimulator(remote: remote)
            if result.0 { c?.updateSwiftCodeRemote(DeviceRow.swiftcodeRemote(remote, running: false)) }
            return result
        }
        c.foldDevice = { [weak self] row, words in
            guard let self else { return (false, "The workspace was closed.") }
            var settings = RemoteSimulatorSettings.load(defaults)
            if let ssh { settings.ssh = ssh }
            guard let remote = RemoteSimulator.hub(settings).first(where: { "\(settings.destination):\($0.remoteDevicePath)" == row.identifier }) else {
                return (false, "Set the remote simulator in Settings ▸ Simulators first.")
            }
            return await self.session.controlRemoteSimulator(remote: remote, words)
        }
        c.deviceSettings = { [weak self] row, words in
            guard let self else { return (false, "The workspace was closed.") }
            var settings = RemoteSimulatorSettings.load(defaults)
            if let ssh { settings.ssh = ssh }
            guard let remote = RemoteSimulator.hub(settings).first(where: { "\(settings.destination):\($0.remoteDevicePath)" == row.identifier }) else {
                return (false, "Set the remote simulator in Settings ▸ Simulators first.")
            }
            return await self.session.controlRemoteSimulator(remote: remote, words)
        }
    }
}
