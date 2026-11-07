import AppKit
import Foundation
import Testing
import YcodeDebug
@testable import YcodeIDECore
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func writeExecutable(_ text: String, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

func writeInfoPlist(_ app: URL, id: String, exe: String) throws {
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": exe, "CFBundlePackageType": "APPL", "CFBundleName": exe,
                                "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0", "MinimumOSVersion": "17.0",
                                "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "UIDeviceFamily": [1]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
}

@MainActor
@Suite(.serialized, .heavyIntegration, .timeLimit(.minutes(15))) struct RunTargetTests {

    @Test func remoteSimulatorCommandsStreamingAndStop() async throws {
        _ = NSApplication.shared
        let root = swiftcodeDir.appendingPathComponent(".build-ide/remote")
        try? FileManager.default.removeItem(at: root)
        let fakeSSH = root.appendingPathComponent("bin/fake-ssh")
        try writeExecutable("""
        #!/bin/sh
        echo "$@" >> "\(root.path)/ssh.log"
        while [ $# -gt 0 ]; do
          case "$1" in
            -o|-l|-p|-i) shift 2 ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        shift
        exec /bin/sh -c "$*"
        """, fakeSSH)
        let fakeSimd = root.appendingPathComponent("bin/swiftcode-simd")
        try writeExecutable("""
        #!/bin/sh
        echo "simd args: $*"
        echo "lean: ${SWIFTCODE_LEAN_BOOT:-off}"
        echo "warm: ${SWIFTCODE_WARM_BOOT:-unset}"
        trap 'echo "stopped by SIGINT"; exit 130' INT
        trap 'echo "stopped by SIGTERM"; exit 143' TERM
        echo "launch dev.swiftcode.remote: ok"
        echo "open: no completion within 60 s, retrying"
        echo "launched dev.swiftcode.remote pid 42"
        echo "hello from the remote app"
        while true; do sleep 0.1; done
        """, fakeSimd)
        let data = root.appendingPathComponent("data")
        let settings = RemoteSimulatorSettings(destination: "tester@fakehost", dataDirectory: data.path, runtimeRoot: "/rr/iOS 27.1",
                                               simdPath: fakeSimd.path, deviceName: "dev1", ssh: fakeSSH.path, rsync: "/usr/bin/rsync")
        let remote = RemoteSimulator(settings: settings)
        let app = root.appendingPathComponent("build/Remote.app")
        try writeInfoPlist(app, id: "dev.swiftcode.remote", exe: "Remote")
        try "binary".write(to: app.appendingPathComponent("Remote"), atomically: true, encoding: .utf8)

        let cmd = remote.runCommand(app: app, bundleID: "dev.swiftcode.remote")
        let full = settings
        #expect(!full.leanBoot)
        #expect(cmd.hasPrefix("echo SWIFTCODE-REMOTE-PID $$; exec env SWIFTCODE_WARM_BOOT=1 '\(fakeSimd.path)'"))
        #expect(!cmd.contains("SWIFTCODE_LEAN_BOOT"))
        var lean = settings
        lean.leanBoot = true
        #expect(RemoteSimulator(settings: lean).runCommand(app: app, bundleID: "dev.swiftcode.remote")
            .hasPrefix("echo SWIFTCODE-REMOTE-PID $$; exec env SWIFTCODE_WARM_BOOT=1 SWIFTCODE_LEAN_BOOT=daemons '\(fakeSimd.path)'"))
        var keep = lean
        keep.keepServices = "com.a.one, com.b.two"
        #expect(RemoteSimulator(settings: keep).runCommand(app: app, bundleID: "dev.swiftcode.remote")
            .contains("exec env SWIFTCODE_WARM_BOOT=1 SWIFTCODE_LEAN_BOOT=daemons SWIFTCODE_LEAN_BOOT_KEEP='com.a.one,com.b.two' '\(fakeSimd.path)'"))
        var keepOnly = settings
        keepOnly.keepServices = "com.a.one"
        #expect(!RemoteSimulator(settings: keepOnly).runCommand(app: app, bundleID: "dev.swiftcode.remote").contains("SWIFTCODE_LEAN_BOOT"))
        #expect(RemoteSimulator(settings: full).runCommand(app: app, bundleID: "dev.swiftcode.remote") == "echo SWIFTCODE-REMOTE-PID $$; exec env SWIFTCODE_WARM_BOOT=1 '\(fakeSimd.path)' --device '\(data.path)/devices/dev1' --runtime-root '/rr/iOS 27.1' --install-app '\(data.path)/apps/Remote.app' --launch 'dev.swiftcode.remote' --environment-overrides '--display-server' 'unix:\(data.path)/display/dev1.sock'")
        #expect(remote.displaySocketPath == "\(data.path)/display/dev1.sock")
        #expect(remote.mkdirCommand(app) == "mkdir -p '\(data.path)/apps' '\(data.path)/display' '\(data.path)/profiles'")
        var cold = full
        cold.warmBoot = false
        #expect(RemoteSimulator(settings: cold).runCommand(app: app, bundleID: "dev.swiftcode.remote").hasPrefix("echo SWIFTCODE-REMOTE-PID $$; exec env SWIFTCODE_WARM_BOOT=0 '\(fakeSimd.path)' --device"))
        #expect(remote.sshArguments("x") == ["-o", "BatchMode=yes", "tester@fakehost", "x"])
        #expect(remote.rsyncArguments(app) == ["-az", "--delete", "-e", "\(fakeSSH.path) -o BatchMode=yes", app.path + "/", "tester@fakehost:\(data.path)/apps/Remote.app/"])
        #expect(RemoteSimulator.quote("it's") == "'it'\\''s'")
        var extra = settings
        extra.additionalArguments = "--timeout-ms 600000 --host-libs '/a b' --shim=\"x y\""
        #expect(RemoteSimulator.words(extra.additionalArguments) == ["--timeout-ms", "600000", "--host-libs", "/a b", "--shim=x y"])
        #expect(RemoteSimulator(settings: extra).runCommand(app: app, bundleID: "dev.swiftcode.remote").hasSuffix("--launch 'dev.swiftcode.remote' --environment-overrides '--display-server' 'unix:\(data.path)/display/dev1.sock' '--timeout-ms' '600000' '--host-libs' '/a b' '--shim=x y'"))
        var ph = RemoteSimulator.Phase.booting
        for l in ["install ok", "open: no completion within 60 s", "open: no completion within 60 s", "launched a.b pid 3"] {
            ph = RemoteSimulator.phase(after: l, current: ph)
            if l.contains("within") { #expect(RemoteSimulator.status(ph, app: "A") == "Launching A") }
        }
        #expect(ph == .running)

        let session = WorkspaceSession(model: try WorkspaceModel(url: try WindowSnapshotTests().samplePackage()))
        await session.runOnRemoteSimulator(app: app, remote: remote)
        #expect(FileManager.default.fileExists(atPath: data.appendingPathComponent("apps/Remote.app/Info.plist").path))
        #expect(await waitUntil(20) { session.console.contains("launch dev.swiftcode.remote: ok") && session.simulatorRun?.remotePID != nil })
        #expect(await waitUntil(20) { session.console.contains("hello from the remote app") })
        #expect(session.consoleText(.target).contains("hello from the remote app") && !session.consoleText(.target).contains("no completion"))
        #expect(session.activity == .running("Running Remote on \(remote.destination.name)"))
        #expect(session.consoleText(.debugger).contains("simd args: --device \(data.path)/devices/dev1 --runtime-root /rr/iOS 27.1 --install-app \(data.path)/apps/Remote.app --launch dev.swiftcode.remote"))
        #expect(session.console.contains("lean: off"))
        #expect(session.console.contains("warm: 1"))
        let pid = try #require(session.simulatorRun?.remotePID)
        session.stopSimulatorRun(remote: remote)
        #expect(await waitUntil(20) { session.simulatorRun == nil })
        #expect(session.console.contains("stopped by SIGINT"))
        #expect(session.console.contains("SwiftCode Simulator ended with status"))
        let log = try String(contentsOf: root.appendingPathComponent("ssh.log"), encoding: .utf8)
        #expect(log.contains("tester@fakehost kill -INT \(pid)"))
        #expect(!log.contains("password"))

        let s2 = WorkspaceSession(model: try WorkspaceModel(url: try WindowSnapshotTests().samplePackage()))
        await s2.runOnRemoteSimulator(app: app, remote: RemoteSimulator(settings: RemoteSimulatorSettings()))
        #expect(s2.console.contains("Settings ▸ Simulators"))
    }

    @Test func settingsPaneAndDestination() throws {
        let t = TestDefaults("remote")
        defer { t.remove() }
        let prefs = Preferences(defaults: t.defaults)
        let pane = SimulatorsSettingsPane(prefs: prefs)
        _ = pane.view
        #expect(!pane.settings.isConfigured)
        pane.update { $0.destination = "u@h"; $0.dataDirectory = "/d"; $0.runtimeRoot = "/r"; $0.simdPath = "/s" }
        #expect(RemoteSimulatorSettings.load(t.defaults).isConfigured && RemoteSimulatorSettings.load(t.defaults).deviceName == "swiftcode-device")
        #expect(RemoteSimulatorSettings.load(t.defaults).warmBoot)
        pane.update { $0.warmBoot = false }
        #expect(!RemoteSimulatorSettings.load(t.defaults).warmBoot)
        #expect(!RemoteSimulatorSettings.load(t.defaults).leanBoot)
        pane.update { $0.leanBoot = true }
        #expect(RemoteSimulatorSettings.load(t.defaults).leanBoot)
        pane.update { $0.leanBoot = false }
        #expect(!RemoteSimulatorSettings.load(t.defaults).leanBoot)
        #expect(WorkspaceWindowController.simulatorAppPath(fromExecutablePath: "/p/.swiftcode-build/Products/Debug/App.app/Contents/MacOS/App")
                == "/p/.swiftcode-build/Products/Debug-iphonesimulator/App.app")
        #expect(WorkspaceWindowController.simulatorAppPath(fromExecutablePath: "/d/Build/Products/Release-iphonesimulator/App.app/App")
                == "/d/Build/Products/Release-iphonesimulator/App.app")
        #expect(Simctl.launchArguments(udid: "U", bundleID: "b.id", waitForDebugger: true)
                == ["launch", "--console", "--terminate-running-process", "--wait-for-debugger", "U", "b.id"])
        #expect(Simctl.launchedPID("b.id: 4242", bundleID: "b.id") == 4242)
    }

    struct ThrowawayDevice {
        let udid: String
        let runtimeVersion: String
        func remove() { TestSimulatorDevices.remove(udid: udid) }
    }

    func createDevice() -> ThrowawayDevice? {
        TestSimulatorDevices.sweepStale()
        let (s, out) = Simctl.xcrun(["list", "-j", "runtimes"])
        guard s == 0, let obj = try? JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any],
              let runtimes = obj["runtimes"] as? [[String: Any]] else { return nil }
        guard let rt = runtimes.last(where: { ($0["isAvailable"] as? Bool) == true && ($0["identifier"] as? String)?.contains(".iOS-") == true }),
              let rtID = rt["identifier"] as? String,
              let type = (rt["supportedDeviceTypes"] as? [[String: Any]])?.first(where: { ($0["productFamily"] as? String) == "iPhone" })?["identifier"] as? String
        else { return nil }
        let (cs, udid) = Simctl.xcrun(["create", TestSimulatorDevices.newName(), type, rtID])
        guard cs == 0 else { return nil }
        let id = udid.trimmingCharacters(in: .whitespacesAndNewlines)
        TestSimulatorDevices.record(id)
        return ThrowawayDevice(udid: id, runtimeVersion: rt["version"] as? String ?? "17.0")
    }

    func buildSimulatorApp(_ dir: URL, id: String, minOS: String) throws -> (app: URL, source: String)? {
        let app = dir.appendingPathComponent("Ticker.app")
        try writeInfoPlist(app, id: id, exe: "Ticker")
        let src = dir.appendingPathComponent("ticker.c")
        try """
        #include <stdio.h>
        #include <unistd.h>
        static int ticks = 0;
        void tick(void) {
            ticks += 1;
            printf("tick %d\\n", ticks);
            fflush(stdout);
        }
        int main(void) {
            printf("hello from the simulator\\n");
            fflush(stdout);
            for (;;) { tick(); usleep(200000); }
        }
        """.write(to: src, atomically: true, encoding: .utf8)
        let sdk = Simctl.run(["/usr/bin/xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let major = minOS.split(separator: ".").first.map(String.init) ?? "17"
        let cc = Simctl.run(["/usr/bin/xcrun", "--sdk", "iphonesimulator", "clang", "-g", "-O0", "-target", "arm64-apple-ios\(major).0-simulator",
                             "-isysroot", sdk, src.path, "-o", app.appendingPathComponent("Ticker").path])
        guard FileManager.default.fileExists(atPath: app.appendingPathComponent("Ticker").path) else { print("clang: \(cc)"); return nil }
        _ = Simctl.run(["/usr/bin/codesign", "--force", "--sign", "-", app.path])
        return (app, src.path)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTCODE_MAC_SIMULATOR_TESTS"] == "1"))
    func runAndDebugOnThrowawayMacSimulator() async throws {
        let heavy = await InterprocessLock.acquire(path: InterprocessLock.debuggerTestLockPath)
        defer { heavy.unlock() }
        guard let device = createDevice() else { print("skipping: no installed iOS simulator runtime"); return }
        defer { device.remove() }
        _ = NSApplication.shared
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/simrun")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = "dev.swiftcode.ticker\(Int.random(in: 1000...9999))"
        guard let (app, source) = try buildSimulatorApp(dir, id: id, minOS: device.runtimeVersion) else { Issue.record("could not build the app"); return }
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"S\")\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let session = WorkspaceSession(model: try WorkspaceModel(url: dir))

        await session.runOnSimulator(app: app, udid: device.udid, debug: false)
        #expect(await waitUntil(240) { session.consoleText(.target).contains("hello from the simulator") && session.console.contains("tick 2") },
                "console: \(session.console.suffix(800))")
        #expect(await waitUntil(60) { session.simulatorRun?.pid != nil }, "no pid")
        session.stopSimulatorRun()
        #expect(await waitUntil(60) { session.simulatorRun == nil }, "still running")

        if InterprocessLock.developerModeDisabled() { print("skipping debug part: Developer Mode disabled"); return }
        session.breakpoints.click(file: source, line: 6)
        await session.runOnSimulator(app: app, udid: device.udid, debug: true)
        let stopped = await waitUntil(120) { session.stoppedThread != nil && session.currentLocation?.line == 6 }
        #expect(stopped, "debug console: \(session.console.suffix(800))")
        if stopped { #expect(session.frames.first?.name.contains("tick") == true) }
        session.stopSimulatorRun()
        session.stop()
        #expect(await waitUntil(60) { session.simulatorRun == nil })
    }
}

extension Simctl {
    static func run(_ argv: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        guard (try? p.run()) != nil else { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self)
    }
}
