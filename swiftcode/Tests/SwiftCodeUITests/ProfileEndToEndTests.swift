#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
import SwiftCodeProfiler
@testable import SwiftCodeUI

@Suite(.serialized, .heavyIntegration) @MainActor struct ProfileEndToEndTests {
    func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }

    @Test func profilesGaugeDemoOnARemoteSimulator() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SWIFTCODE_E2E_PROFILE"] == "1", let destination = env["SWIFTCODE_E2E_REMOTE"], let data = env["SWIFTCODE_E2E_DATA"],
              let runtime = env["SWIFTCODE_E2E_RUNTIME"], let simd = env["SWIFTCODE_E2E_SIMD"] else {
            log("skipping: SWIFTCODE_E2E_PROFILE and friends are not set")
            return
        }
        _ = NSApplication.shared
        let scratch = TestDefaults("e2e-profile")
        defer { scratch.remove() }
        let defaults = scratch.defaults
        var settings = RemoteSimulatorSettings(destination: destination, dataDirectory: data, runtimeRoot: runtime,
                                               simdPath: simd, deviceName: env["SWIFTCODE_E2E_DEVICE"] ?? "gauge")
        settings.warmBoot = env["SWIFTCODE_E2E_WARM_BOOT"] != "0"
        settings.save(defaults)
        let saved = Preferences.shared
        Preferences.shared = Preferences(defaults: defaults)
        defer { Preferences.shared = saved }

        let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let project = swiftcodeDir.appendingPathComponent("Tools/gauge-samples/GaugeDemo/GaugeDemo.xcodeproj")
        let session = WorkspaceSession(model: try WorkspaceModel(url: project))
        session.engine = (BuildSystemPreference(rawValue: env["SWIFTCODE_E2E_ENGINE"] ?? "xcodebuild") ?? .xcodebuild).makeEngine()
        let type = env["SWIFTCODE_E2E_TYPE"] ?? "iphone-18-pro"
        let target = try #require(RemoteSimulatorSettings.load(defaults).targets.first { $0.deviceType.id == type })
        log("e2e profile: destination \(target.destination.name) \(target.runtimeVersion ?? "?"), device directory \(target.deviceDirectoryName)")
        let wc = WorkspaceWindowController(session: session, loadDestinations: false, startLanguageService: false)
        session.destination = target.destination
        session.scheme = "GaugeDemo"
        #expect(session.destination?.isSwiftCodeRemoteSimulator == true)
        let started = Date()
        let gauge = try #require(wc.profileScheme(building: true))
        let minutes = Double(env["SWIFTCODE_E2E_MINUTES"] ?? "30") ?? 30
        log("e2e profile: Profile started (build, upload, launch)")
        let mirror = env["SWIFTCODE_E2E_CONSOLE"].map { URL(fileURLWithPath: $0) }
        var mirrored = 0
        func mirrorConsole() {
            guard let mirror, session.console.count != mirrored else { return }
            mirrored = session.console.count
            try? Data(("phase \(gauge.model.phase)\n" + session.console).utf8).write(to: mirror)
        }
        let launched = await waitUntil(minutes * 60) {
            mirrorConsole()
            if case .failed = gauge.model.phase { return true }
            return session.console.contains("launched dev.swiftcode.GaugeDemo")
        }
        log(String(format: "e2e profile: launched after %.0f s", Date().timeIntervalSince(started)))
        #expect(launched && session.console.contains("launched dev.swiftcode.GaugeDemo"))
        let seconds = Double(env["SWIFTCODE_E2E_SECONDS"] ?? "15") ?? 15
        _ = await waitUntil(seconds) { session.simulatorRun == nil }
        gauge.recordButton.performClick(nil)
        let loaded = await waitUntil(300) {
            mirrorConsole()
            if case .recording = gauge.model.phase { return false }
            return true
        }
        mirrorConsole()
        log("---- remote console ----\n" + String(session.console.suffix(5000)))
        #expect(loaded && gauge.model.phase == .loaded)
        let trace = try #require(gauge.model.trace)
        log(GaugeReport.summary(trace, top: 12))
        let top = CallTree.topFunctions(trace: trace).prefix(5).map(\.name)
        #expect(top.contains("sieve_primes") || top.contains("multiply_matrices"))
        let crunch = trace.signposts.filter { $0.name == "Crunch" }
        #expect(!crunch.isEmpty)
        #expect(trace.signposts.contains { $0.name == "Sieve" } && trace.signposts.contains { $0.name == "Matrix" })
        if let node = gauge.model.tree?.root.find("sieve_primes") {
            gauge.model.selectedPath = node.path
            #expect(gauge.model.annotation?.file?.hasSuffix("Work.c") == true)
        }
        if let png = env["SWIFTCODE_E2E_PNG"] {
            gauge.window?.setContentSize(NSSize(width: 1440, height: 900))
            gauge.model.content = .callTree
            #expect(gauge.writeSnapshot(to: URL(fileURLWithPath: png)))
            log("e2e profile: window snapshot \(png)")
        }
        gauge.close()
    }

}
#endif
