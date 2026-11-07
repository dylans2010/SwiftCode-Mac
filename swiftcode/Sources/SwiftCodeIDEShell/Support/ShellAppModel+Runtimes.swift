import Foundation
import SwiftCodeIDECore

extension ShellAppModel {
    public func showRuntimeSetup(step: RuntimeSetupStep? = nil) {
        let s = runtimeSetup ?? RuntimeSetupSession(defaults: runtimeDefaults)
        runtimeSetup = s
        let t = s.recheck()
        if let step { s.show(step) } else {
            Task { @MainActor in
                await t.value
                s.openOnFirstProblem()
            }
        }
    }

    public func closeRuntimeSetup() {
        runtimeSetup?.stop()
        runtimeSetup = nil
    }

    @discardableResult
    public func offerRuntimeSetupAtFirstLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> Task<Void, Never>? {
        let d = runtimeDefaults
        let drivers = ["SWIFTCODE_NO_FIRST_LAUNCH", "OV_QUIT_AFTER", "SWIFTCODE_IDE_SCRIPT", "SWIFTCODE_IDE_WALK", "SWIFTCODE_IDE_PARITY", "SWIFTCODE_IDE_REMOTE_RUN"]
        guard !d.bool(forKey: RuntimeSetupChoices.offeredKey), !drivers.contains(where: { environment[$0] != nil }) else { return nil }
        d.set(true, forKey: RuntimeSetupChoices.offeredKey)
        let choices = RuntimeSetupChoices.load(d)
        let machine = SetupMachine.current
        return Task { @MainActor [weak self] in
            let r = await RuntimeSetupChecker(machine: machine, choices: choices).run()
            if !machine.canRunSimulatorHere || choices.useHost || r.readyPlatforms.isEmpty { self?.showRuntimeSetup() }
        }
    }
}
