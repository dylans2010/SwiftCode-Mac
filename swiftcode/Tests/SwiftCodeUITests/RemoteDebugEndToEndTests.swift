#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

@Suite(.serialized, .heavyIntegration) @MainActor struct RemoteDebugEndToEndTests {
    @Test func stopsAtABreakpointOnARealRemoteSimulator() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let destination = env["SWIFTCODE_E2E_REMOTE"], let data = env["SWIFTCODE_E2E_DATA"], let runtime = env["SWIFTCODE_E2E_RUNTIME"],
              let simd = env["SWIFTCODE_E2E_SIMD"], let appPath = env["SWIFTCODE_E2E_APP"], let file = env["SWIFTCODE_E2E_DEBUG_FILE"],
              let line = env["SWIFTCODE_E2E_DEBUG_LINE"].flatMap(Int.init) else {
            print("skipping: SWIFTCODE_E2E_REMOTE, SWIFTCODE_E2E_DEBUG_FILE and friends are not set")
            return
        }
        _ = NSApplication.shared
        var settings = RemoteSimulatorSettings(destination: destination, dataDirectory: data, runtimeRoot: runtime,
                                               simdPath: simd, deviceName: env["SWIFTCODE_E2E_DEVICE"] ?? "e2e")
        if let lean = env["SWIFTCODE_E2E_LEAN_BOOT"] { settings.leanBoot = lean == "1" }
        settings.warmBoot = env["SWIFTCODE_E2E_WARM_BOOT"] != "0"
        if let extra = env["SWIFTCODE_E2E_SIMD_ARGS"] { settings.additionalArguments = extra }
        let remote = RemoteSimulator(settings: settings)
        let app = URL(fileURLWithPath: appPath)
        let bundle = try #require(AppBundle(url: app))
        let minutes = Double(env["SWIFTCODE_E2E_MINUTES"] ?? "30") ?? 30

        let session = WorkspaceSession(model: try WorkspaceModel(url: try WindowSnapshotTests().samplePackage()))
        session.breakpoints.click(file: file, line: line)
        await session.runOnRemoteSimulator(app: app, remote: remote)
        let launched = await waitUntil(minutes * 60) { session.console.contains("launched \(bundle.bundleID)") || session.simulatorRun == nil }
        #expect(launched && session.simulatorRun != nil)
        let stopped = await waitUntil(300) { session.stoppedThread != nil && session.frames.first?.line == line }
        print("---- remote console ----\n" + String(session.console.suffix(4000)))
        #expect(stopped)
        guard stopped else {
            session.stopSimulatorRun(remote: remote)
            _ = await waitUntil(remote.stopGrace) { session.simulatorRun == nil }
            return
        }
        #expect(await waitUntil(60) { !session.isLoadingVariables && !session.variables.isEmpty })
        #expect(await waitUntil(30) { if case .paused = session.activity { true } else { false } })
        print("e2e debug: activity \(session.activity); frames: " + session.frames.prefix(4).map { "\($0.name) \($0.file ?? "-"):\($0.line)" }.joined(separator: " | "))
        print("e2e debug: variables: " + session.variables.map { "\($0.name)=\($0.value)" }.joined(separator: ", "))
        #expect(session.frames.first?.line == line)
        #expect(session.frames.first?.file?.hasSuffix((file as NSString).lastPathComponent) == true)
        #expect(!session.variables.isEmpty)
        if let round = session.variables.first(where: { $0.name == "round" }) { #expect(Int(round.value) != nil) }
        let product = await session.evaluateInConsole("expression round * 2")
        print("e2e debug: expression round * 2 -> \(product ?? "nil")")
        #expect(product.map { !$0.contains("error") && $0.contains("Int") } == true)
        let before = session.frames.first?.line
        await session.step("over")
        #expect(await waitUntil(60) { session.stoppedThread != nil && session.frames.first?.line != before && !session.isLoadingVariables })
        print("e2e debug: variables after step: " + session.variables.map { "\($0.name)=\($0.value)" }.joined(separator: ", "))
        #expect(session.variables.contains { $0.name == "n" })
        print("e2e debug: after step over: " + (session.frames.first.map { "\($0.name):\($0.line)" } ?? "-"))
        await session.continueOrPause()
        #expect(await waitUntil(60) { session.stoppedThread != nil && session.frames.first?.line == line })
        session.stopSimulatorRun(remote: remote)
        #expect(await waitUntil(remote.stopGrace) { session.simulatorRun == nil })
        print("---- after Stop ----\n" + String(session.console.suffix(2000)))
    }
}
#endif
