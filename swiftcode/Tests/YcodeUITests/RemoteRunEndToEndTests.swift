#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import YcodeIDECore
@testable import YcodeUI

@Suite(.serialized, .heavyIntegration) @MainActor struct RemoteRunEndToEndTests {
    @Test func runsAnAppOnARealRemoteSimulator() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let destination = env["SWIFTCODE_E2E_REMOTE"], let data = env["SWIFTCODE_E2E_DATA"], let runtime = env["SWIFTCODE_E2E_RUNTIME"],
              let simd = env["SWIFTCODE_E2E_SIMD"], let appPath = env["SWIFTCODE_E2E_APP"] else {
            print("skipping: SWIFTCODE_E2E_REMOTE and friends are not set")
            return
        }
        _ = NSApplication.shared
        var settings = RemoteSimulatorSettings(destination: destination, dataDirectory: data, runtimeRoot: runtime,
                                               simdPath: simd, deviceName: env["SWIFTCODE_E2E_DEVICE"] ?? "e2e")
        if let lean = env["SWIFTCODE_E2E_LEAN_BOOT"] { settings.leanBoot = lean == "1" }
        settings.warmBoot = env["SWIFTCODE_E2E_WARM_BOOT"] != "0"
        let remote = RemoteSimulator(settings: settings)
        let app = URL(fileURLWithPath: appPath)
        let bundle = try #require(AppBundle(url: app))
        let minutes = Double(env["SWIFTCODE_E2E_MINUTES"] ?? "30") ?? 30

        let session = WorkspaceSession(model: try WorkspaceModel(url: try WindowSnapshotTests().samplePackage()))
        let started = Date()
        await session.runOnRemoteSimulator(app: app, remote: remote)
        #expect(await waitUntil(60) { session.simulatorRun?.remotePID != nil })
        var homeAt: Double?
        let launched = await waitUntil(minutes * 60) {
            if homeAt == nil, session.console.contains("swiftcode-sim: home screen at") { homeAt = Date().timeIntervalSince(started) }
            return session.console.contains("launched \(bundle.bundleID)") || session.simulatorRun == nil
        }
        let launchedAt = Date().timeIntervalSince(started)
        print(String(format: "e2e timing: home screen %@ s, app launched %.1f s after Run (warm boot %@)",
                     homeAt.map { String(format: "%.1f", $0) } ?? "-", launchedAt, settings.warmBoot ? "on" : "off"))
        print("---- remote console ----\n" + String(session.console.suffix(6000)))
        #expect(launched && session.console.contains("launched \(bundle.bundleID)"))
        #expect(session.simulatorRun != nil)
        guard session.simulatorRun != nil else { return }
        let stoppedAt = Date()
        session.stopSimulatorRun(remote: remote)
        #expect(session.activity == .running(RemoteSimulator.stoppingStatus(app: bundle.executable, saves: settings.warmBoot)))
        #expect(await waitUntil(remote.stopGrace - 10) { session.simulatorRun == nil })
        print(String(format: "e2e timing: run ended %.1f s after Stop", Date().timeIntervalSince(stoppedAt)))
        print("---- after Stop ----\n" + String(session.console.suffix(2000)))
        if settings.warmBoot {
            #expect(session.consoleText(.debugger).contains("swiftcode-sim: warm boot: the device was saved; the next run continues from it"))
            #expect(!session.console.contains("the device was not saved"))
        }
        #expect(session.console.contains("SwiftCode Simulator stopped") || session.console.contains("SwiftCode Simulator ended with status"))
        #expect(!session.console.contains("the stop signal did not reach"))
        #expect(!session.console.contains("after Stop; closing the connection"))
        #expect(session.activity == .finished("Finished running \(bundle.executable) on \(remote.destination.name)"))
    }
}
#endif
