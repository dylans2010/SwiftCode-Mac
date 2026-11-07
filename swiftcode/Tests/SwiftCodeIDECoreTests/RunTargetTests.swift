import Foundation
import Testing
import SwiftCodeDebug
@testable import SwiftCodeIDECore

@MainActor
@Suite(.serialized, .heavyIntegration, .timeLimit(.minutes(15))) struct RunTargetTests {
    @Test func leanBootSettingMigratesToFullBoot() throws {
        let t = TestDefaults("remote-lean")
        defer { t.remove() }
        t.defaults.set(true, forKey: RemoteSimulatorSettings.leanBootLegacyKey)
        var s = RemoteSimulatorSettings.load(t.defaults)
        #expect(!s.leanBoot)
        s.deviceName = "other"
        s.save(t.defaults)
        #expect(t.defaults.object(forKey: RemoteSimulatorSettings.leanBootLegacyKey) == nil)
        #expect(t.defaults.object(forKey: RemoteSimulatorSettings.leanBootKey) as? Bool == false)
        s.leanBoot = true
        s.save(t.defaults)
        #expect(RemoteSimulatorSettings.load(t.defaults).leanBoot)
        #expect(RemoteSimulatorSettings.load(t.defaults).leanBoot)
        #expect(RemoteSimulator(settings: RemoteSimulatorSettings.load(t.defaults)).leanBootVariables == "SWIFTCODE_LEAN_BOOT=daemons ")
    }
}
