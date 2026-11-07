import Foundation
import Testing
import SwiftCodeBuild
import SwiftCodeIDECore
import SwiftCodeSimLink
@testable import SwiftCodeIDEShell

@Suite(.serialized) struct SimulatorUXTests {
    @Test func aHostWithoutDevicesOffersTheDeviceRunMakes() throws {
        let d = try #require(ShellRemoteRun.newDeviceDestination(host: "thor", deviceTypes: ["iphone-duo", "iphone-18-pro", "ipad-a16"],
                                                                 runtime: "/rt/iOS-27.1-24A94401/RuntimeRoot"))
        #expect(d.name == "iPhone 18 Pro (thor)" && d.deviceType == "iphone-18-pro" && d.osVersion == "27.1")
        #expect(ShellRemoteRun.target(of: d)?.device == "iPhone-18-Pro")
        #expect(ShellRemoteRun.newDeviceDestination(host: "thor", deviceTypes: ["iphone-duo"], runtime: nil)?.deviceType == "iphone-duo")
        #expect(ShellRemoteRun.newDeviceDestination(host: "thor", deviceTypes: ["vision-pro"], runtime: nil) == nil)
        #expect(ShellRemoteRun.deviceDirectoryName("iPad Pro 13-inch (M5)") == "iPad-Pro-13-inch--M5-")
    }

    @Test func progressAndFailureTexts() {
        #expect(ShellRemoteRun.bootingLine(device: "P", seconds: 30) == "Booting P… 30 s\n")
        #expect(ShellRemoteRun.bootedLine(device: "P", seconds: 42) == "P is running (42 s).\n")
        let m = ShellRemoteRun.stoppedWhileBootingMessage(device: "P", host: "thor", log: ["a", "", "swiftcode-simd: no runtime"])
        #expect(m.hasPrefix("P stopped on thor before its display came up.") && m.hasSuffix("  a\n  swiftcode-simd: no runtime"))
    }

    @Test func cancelEndsTheBuildProcess() async throws {
        let cancel = RemoteRunCancel()
        let started = Date()
        Task.detached {
            try? await Task.sleep(nanoseconds: 300_000_000)
            cancel.cancel()
        }
        let status = try await ShellRemoteRun.runProcess(["/bin/sleep", "30"], output: { _ in }, started: cancel.started)
        #expect(cancel.isCancelled && status != 0)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        private var phaseItems: [RemoteRunPhase] = []
        func add(_ s: String) { lock.withLock { items.append(s) } }
        func add(_ p: RemoteRunPhase) { lock.withLock { phaseItems.append(p) } }
        var text: String { lock.withLock { items.joined() } }
        var phases: [RemoteRunPhase] { lock.withLock { phaseItems } }
    }

    func host(delay: Double, fail: Bool = false, appLaunchAfter: Double? = nil) throws -> (SimHostService, LinkClient, LinkHost, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-simux-\(UUID().uuidString)")
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let launcher = home.appendingPathComponent("bin/swiftcode-sim")
        let body = fail ? "echo 'swiftcode-simd: the runtime root has no dyld_sim' >&2; exit 3"
            : "for a in \"$@\"; do case \"$a\" in unix:*) sock=${a#unix:} ;; esac; done\nsleep \(delay)\nmkdir -p \"$(dirname \"$sock\")\" && : > \"$sock\"\n"
                + (appLaunchAfter.map { "sleep \($0)\necho 'swiftcode-simd: app launch: open request took 800 ms'\n" } ?? "") + "sleep 30"
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: launcher)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        let port = Int.random(in: 46000..<46900)
        let config = try SimHostConfig.load(text: """
            SWIFTCODE_SIM_HOME=\(home.path)
            SWIFTCODE_SIM_TREE=\(dir.path)
            SWIFTCODE_SIM_RUNTIME=\(dir.path)/RuntimeRoot
            SWIFTCODE_SIMHOST_LISTEN=127.0.0.1:\(port)
            SWIFTCODE_SIMHOST_MEDIA_PORT=\(port + 1)
            SWIFTCODE_SIMHOST_NAME=loop
            """, environment: [:])
        let hostStore = LinkStore(directory: dir.appendingPathComponent("host-link"))
        let clientStore = LinkStore(directory: dir.appendingPathComponent("client-link"))
        try hostStore.addPeer(TrustedPeer(name: "client", publicKey: try clientStore.identity().publicKey, role: "client"))
        try clientStore.addPeer(TrustedPeer(name: "loop", publicKey: try hostStore.identity().publicKey, role: "host",
                                            address: "127.0.0.1:\(port)", mediaPort: port + 1))
        let service = try SimHostService(config: config, store: hostStore)
        try service.start()
        let client = try LinkClient(store: clientStore, clientName: "client")
        return (service, client, try client.host(named: "loop"), dir)
    }

    func waitFor(_ lines: Lines, seconds: Double, _ done: (Lines) -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !done(lines) { try? await Task.sleep(nanoseconds: 100_000_000) }
    }

    @Test func runMakesTheDeviceThenReportsBootProgress() async throws {
        let (service, client, h, dir) = try host(delay: 2.5)
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        let lines = Lines()
        let c = try client.control(h)
        #expect(try ShellRemoteRun.ensureDevice(c, device: "iPhone-18-Pro", type: "iphone-18-pro", host: h.name, output: lines.add))
        #expect(lines.text.contains("Created iPhone-18-Pro. Its first boot sets the device up"))
        #expect(try !ShellRemoteRun.ensureDevice(c, device: "iPhone-18-Pro", type: "iphone-18-pro", host: h.name, output: lines.add))
        #expect(try c.request(LinkRequest(op: "boot", device: "iPhone-18-Pro")).ok)
        let restart = Lines()
        #expect(try !ShellRemoteRun.ensureDevice(c, device: "iPhone-18-Pro", type: "iphone-18-pro", host: h.name, output: restart.add))
        #expect(restart.text == ShellRemoteRun.restartLine(device: "iPhone-18-Pro"))
        c.close()
        ShellRemoteRun.watchBoot(host: h, device: "iPhone-18-Pro", client: client, every: 1, output: lines.add, phase: lines.add)
        await waitFor(lines, seconds: 20) { !$0.phases.isEmpty }
        #expect(lines.phases == [.running], "\(lines.text)")
        #expect(lines.text.contains("Booting iPhone-18-Pro… "))
        #expect(lines.text.contains("iPhone-18-Pro is running ("))
    }

    @Test func aRunWaitsForTheAppToOpen() async throws {
        let (service, client, h, dir) = try host(delay: 0.5, appLaunchAfter: 2.5)
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        let lines = Lines()
        let c = try client.control(h)
        _ = try ShellRemoteRun.ensureDevice(c, device: "P", type: "iphone-18-pro", host: h.name, output: lines.add)
        #expect(try c.request(LinkRequest(op: "boot", device: "P")).ok)
        c.close()
        ShellRemoteRun.watchBoot(host: h, device: "P", app: "Hello", client: client, every: 1, output: lines.add, phase: lines.add)
        await waitFor(lines, seconds: 20) { !$0.phases.isEmpty }
        #expect(lines.phases == [.running], "\(lines.text)")
        #expect(lines.text.contains("P's display is up (") && lines.text.contains("Hello is open on P ("), "\(lines.text)")
    }

    @Test func appLaunchStateFromTheLog() {
        #expect(ShellRemoteRun.appLaunchState(log: ["swiftcode-simd: display server: …"]) == .waiting)
        #expect(ShellRemoteRun.appLaunchState(log: ["x", "swiftcode-simd: app launch: open request took 812 ms"]) == .opened)
        #expect(ShellRemoteRun.appLaunchState(log: ["swiftcode-simd: app install: failed: no Info.plist"])
                == .failed("swiftcode-simd: app install: failed: no Info.plist"))
    }

    @Test func aDeviceThatStopsWhileBootingFailsWithTheHostsLog() async throws {
        let (service, client, h, dir) = try host(delay: 0, fail: true)
        defer {
            service.stop()
            try? FileManager.default.removeItem(at: dir)
        }
        let lines = Lines()
        let c = try client.control(h)
        _ = try ShellRemoteRun.ensureDevice(c, device: "P", type: "iphone-18-pro", host: h.name, output: lines.add)
        #expect(try c.request(LinkRequest(op: "boot", device: "P")).ok)
        c.close()
        ShellRemoteRun.watchBoot(host: h, device: "P", client: client, every: 1, output: lines.add, phase: lines.add)
        await waitFor(lines, seconds: 20) { !$0.phases.isEmpty }
        guard case .failed(let why) = lines.phases.first else {
            Issue.record("no failure: \(lines.phases) \(lines.text)")
            return
        }
        #expect(why.contains("P stopped on loop before its display came up") && why.contains("has no dyld_sim"), "\(why)")
    }
}

extension SimulatorUXTests {
    @Test func toolsRootFromEveryBuildLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-tools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("scripts/swiftcode-ios-build-linux").path, contents: Data())
        for exe in [".build/out/Products/Debug-linux-x86_64/swiftcode-ide", ".build/debug/swiftcode-ide", "bin/swiftcode-ide"] {
            #expect(ShellRemoteRun.toolsRoot(executable: root.appendingPathComponent(exe).path).standardizedFileURL.path
                    == root.standardizedFileURL.path, "\(exe)")
        }
    }
}

extension SimulatorUXTests {
    @Test func anIOSAppOpensOnASimulatorHostsDevice() {
        let mine = Destination(name: "My Computer", specifier: "platform=Linux", platform: "Linux", kind: .mac)
        let offline = ShellRemoteRun.offlineDestination(host: "a")
        let p = ShellRemoteRun.destination(host: "b", device: LinkDeviceInfo(name: "P", deviceType: "iphone-18-pro", runtime: "/rt/iOS-27.1-x/RuntimeRoot", state: "shutdown"))
        let groups = [DestinationGroup(title: "My Computer", destinations: [mine]), DestinationGroup(title: "a", destinations: [offline]),
                      DestinationGroup(title: "b", destinations: [p])]
        #expect(ShellRemoteRun.defaultDestination(groups, productPlatform: "iOS") == p)
        #expect(ShellRemoteRun.defaultDestination(groups, productPlatform: "macOS") == nil)
        #expect(ShellRemoteRun.defaultDestination(Array(groups.prefix(2)), productPlatform: "iOS") == nil)
    }
}
