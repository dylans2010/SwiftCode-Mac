import AppKit
import Foundation
import Testing
import YcodeBuild
@testable import YcodeIDECore
import YcodeProject
@testable import YcodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized, .timeLimit(.minutes(5))) struct SimulatorSideR37Tests {

    func withPrefs(_ tag: String, _ body: (Preferences, URL) async throws -> Void) async throws {
        let t = TestDefaults("r37-\(tag)")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-r37-\(tag)-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Preferences(defaults: t.defaults, themesDirectory: dir.appendingPathComponent("Themes"))
        let old = Preferences.shared
        Preferences.shared = p
        defer {
            Preferences.shared = old
            NotificationCenter.default.post(name: Preferences.didChange, object: nil)
            t.remove()
            try? FileManager.default.removeItem(at: dir)
        }
        try await body(p, dir)
    }

    func iosApp(in dir: URL, name: String = "Tour") throws -> URL {
        var o = ProjectOptions()
        o.deploymentTarget = "18.0"
        o.productName = name
        o.organizationIdentifier = "org.swiftcode.tests"
        o.testing = .none
        o.setStorage(.none)
        return try ProjectTemplate.app.create(platform: "iOS", options: o, in: dir)
    }

    func sim(_ name: String, _ version: String) -> Destination {
        Destination(name: name, specifier: "platform=iOS Simulator,id=\(name)-\(version)", platform: "iOS", kind: .simulator,
                    osVersion: version, identifier: "\(name)-\(version)")
    }

    func window(_ proj: URL, state: URL) throws -> WorkspaceWindowController {
        _ = NSApplication.shared
        return WorkspaceWindowController(session: WorkspaceSession(model: try WorkspaceModel(url: proj)), loadDestinations: false,
                                         startLanguageService: false, openFirstFile: false, userStateURL: state)
    }

    struct Remote {
        let root: URL
        let settings: RemoteSimulatorSettings
        var remote: RemoteSimulator { RemoteSimulator(settings: settings) }
        var log: String { (try? String(contentsOf: root.appendingPathComponent("ssh.log"), encoding: .utf8)) ?? "" }
        var data: URL { root.appendingPathComponent("data") }
        func touch(_ name: String) { FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: nil) }
    }

    func makeRemote(_ tag: String, launcher: String, slowRsync: Bool = false, runtimeRoot: String? = nil) throws -> Remote {
        let root = swiftcodeDir.appendingPathComponent(".build-ide/r37-\(tag)-\(UUID().uuidString.prefix(8))")
        let ssh = root.appendingPathComponent("bin/fake-ssh")
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
        case "$*" in
          kill\\ *) [ -e "\(root.path)/fail-kill" ] && exit 255 ;;
          *SWIFTCODE-REMOTE-PID*) [ -e "\(root.path)/delay-run" ] && sleep 1 ;;
        esac
        exec /bin/sh -c "$*"
        """, ssh)
        let rsync = root.appendingPathComponent("bin/rsync")
        try writeExecutable("""
        #!/bin/sh
        \(slowRsync ? "sleep 1.5" : "")
        exec /usr/bin/rsync "$@"
        """, rsync)
        let simd = root.appendingPathComponent("bin/swiftcode-sim")
        try writeExecutable(launcher, simd)
        let data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        var s = RemoteSimulatorSettings(destination: "tester@fakehost", dataDirectory: data.path, runtimeRoot: runtimeRoot ?? root.appendingPathComponent("rr").path,
                                        simdPath: simd.path, deviceName: "dev1", ssh: ssh.path, rsync: rsync.path)
        s.runtimeVersion = RemoteSimulatorSettings.version(inPath: s.runtimeRoot)
        return Remote(root: root, settings: s)
    }

    func app(in root: URL) throws -> URL {
        let app = root.appendingPathComponent("build/Remote.app")
        try writeInfoPlist(app, id: "dev.swiftcode.remote", exe: "Remote")
        try "binary".write(to: app.appendingPathComponent("Remote"), atomically: true, encoding: .utf8)
        return app
    }

    func session() throws -> WorkspaceSession {
        WorkspaceSession(model: try WorkspaceModel(url: try WindowSnapshotTests().samplePackage()))
    }

    @Test func runtimeVersionFromPathPlistAndDefaults() throws {
        #expect(RemoteSimulatorSettings.version(inPath: "/rt/iOS_27.1.simruntime/Contents/Resources/RuntimeRoot") == "27.1")
        #expect(RemoteSimulatorSettings.version(inPath: "/rr/iOS 27.1") == "27.1")
        #expect(RemoteSimulatorSettings.version(inPath: "/data/swiftcode/runtime") == nil)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["ProductName": "x", "ProductVersion": "27.1"], format: .binary, options: 0)
        #expect(RemoteSimulator.productVersion(plist: plist) == "27.1")
        #expect(RemoteSimulator.productVersion(plist: Data("nope".utf8)) == nil)

        let t = TestDefaults("r37-version")
        defer { t.remove() }
        var s = RemoteSimulatorSettings(destination: "u@h", dataDirectory: "/d", runtimeRoot: "/data/rt", simdPath: "/s")
        s.save(t.defaults)
        #expect(RemoteSimulatorSettings.load(t.defaults).runtimeVersion == nil)
        RemoteSimulatorSettings.saveRuntimeVersion("27.1", root: "/data/rt", t.defaults)
        #expect(RemoteSimulatorSettings.load(t.defaults).runtimeVersion == "27.1")
        s.runtimeRoot = "/data/rt2"
        s.save(t.defaults)
        #expect(RemoteSimulatorSettings.load(t.defaults).runtimeVersion == nil)
        #expect(!RemoteSimulatorSettings.hasRuntimeVersion(for: "/data/rt2", t.defaults))

        let d = RemoteSimulator.destination(runtimeVersion: "27.1")
        #expect(d.name == "SwiftCode Simulator" && d.osVersion == "27.1" && d.isSwiftCodeRemoteSimulator && RemoteSimulator.destination.isSwiftCodeRemoteSimulator)
        #expect(DestinationMenuModel.submenuTitle(d) == "SwiftCode Simulator 27.1")
        #expect(!sim("iPhone 17", "27.1").isSwiftCodeRemoteSimulator)
    }

    @Test func remoteSimulatorSortsWithTheSimulatorsByRuntime() {
        let sims = [sim("iPhone 17", "26.4"), sim("iPad Air", "27.1"), sim("iPhone 18", "27.1")]
        let model = DestinationMenuModel(current: nil, devices: [], simulators: sims + [RemoteSimulator.destination(runtimeVersion: "27.1")],
                                         platforms: ["iOS"], designedForIPad: true)
        #expect(model.sections.map(\.title) == ["Devices", "Simulators", "Build"])
        #expect(model.rows("Simulators").map(DestinationMenuModel.submenuTitle) == ["iPhone 18 27.1", "iPad Air 27.1", "SwiftCode Simulator 27.1", "iPhone 17 26.4"])
        let older = DestinationMenuModel(current: nil, devices: [], simulators: sims + [RemoteSimulator.destination(runtimeVersion: "26.0")], platforms: ["iOS"])
        #expect(older.rows("Simulators").last?.isSwiftCodeRemoteSimulator == true)
        let unknown = DestinationMenuModel(current: nil, devices: [], simulators: sims + [RemoteSimulator.destination], platforms: ["iOS"])
        #expect(unknown.rows("Simulators").map(DestinationMenuModel.submenuTitle) == ["iPhone 18 27.1", "iPad Air 27.1", "SwiftCode Simulator", "iPhone 17 26.4"])
        let mac = DestinationMenuModel(current: nil, devices: [], simulators: sims + [RemoteSimulator.destination(runtimeVersion: "27.1")], platforms: ["macOS"])
        #expect(mac.rows("Simulators").isEmpty)
        #expect(mac.incompatible.contains { $0.isSwiftCodeRemoteSimulator && $0.name == "SwiftCode Simulator (mismatched platform)" })
    }

    @Test func destinationMenusListTheRemoteSimulatorUnderSimulators() async throws {
        try await withPrefs("menu") { p, dir in
            var remote = RemoteSimulatorSettings()
            remote.destination = "tester@sim-host"
            remote.dataDirectory = "/data/swiftcode"
            remote.runtimeRoot = "/data/swiftcode/iOS_27.1.simruntime"
            remote.simdPath = "/data/swiftcode/bin/swiftcode-sim"
            remote.save(p.defaults)
            let wc = try window(try iosApp(in: dir), state: dir.appendingPathComponent("state.json"))
            wc.setDestinationGroups(DestinationCatalog.groups(devices: [], simulators: [sim("iPhone 17", "26.4"), sim("iPhone 18", "27.1")]))
            let menu = try #require(wc.destinationPopUp.menu)
            let titles = menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
            #expect(!titles.contains("SwiftCode"))
            let simsHeader = try #require(titles.firstIndex(of: "Simulators"))
            let buildHeader = try #require(titles.firstIndex(of: "Build"))
            let remoteIndex = try #require(menu.items.firstIndex { ($0.representedObject as? String) == RemoteSimulator.identifier })
            #expect(remoteIndex > simsHeader && remoteIndex < buildHeader)
            #expect(menu.items[remoteIndex].title.hasPrefix("iPhone Duo (SwiftCode)"))
            menu.delegate?.menuNeedsUpdate?(menu)
            #expect(menu.items[remoteIndex].attributedTitle?.string == "iPhone Duo (SwiftCode)\t27.1")
            let rowTitles = menu.items[(simsHeader + 1)..<buildHeader].filter { !$0.isSeparatorItem }.map { $0.title.components(separatedBy: "\t")[0] }
            #expect(rowTitles == ["iPhone 18", "iPhone Duo (SwiftCode)", "iPad (A16) (SwiftCode)", "iPad Pro 13-inch (M5) (SwiftCode)", "iPhone 17"])

            let bar = MainMenu.make()
            let sub = try #require(bar.item(withTitle: "Product")?.submenu?.item(withTitle: "Destination")?.submenu)
            DynamicMenus.fillDestinations(sub, model: wc.destinationMenuModel(), current: wc.session.destination, target: wc)
            let subTitles = sub.items.map { $0.isSeparatorItem ? "—" : $0.title }
            let s = try #require(subTitles.firstIndex(of: "Simulators"))
            #expect(Array(subTitles[(s + 1)...(s + 5)]) == ["iPhone 18 27.1", "iPhone Duo (SwiftCode) 27.1", "iPad (A16) (SwiftCode) 27.1",
                                                          "iPad Pro 13-inch (M5) (SwiftCode) 27.1", "iPhone 17 26.4"])
            #expect(subTitles.filter { $0.contains("(SwiftCode)") }.count == 3)

            wc.selectDestinationRow(RemoteSimulator.identifier)
            #expect(wc.session.destination?.isSwiftCodeRemoteSimulator == true && wc.session.destination?.osVersion == "27.1")
            #expect(WorkspaceWindowController.symbol(for: wc.session.destination!) == "candybarphone")
        }
    }

    @Test func runtimeVersionIsReadFromTheHostOnce() async throws {
        let r = try makeRemote("version", launcher: "#!/bin/sh\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: r.root) }
        let core = URL(fileURLWithPath: r.settings.runtimeRoot).appendingPathComponent("System/Library/CoreServices")
        try FileManager.default.createDirectory(at: core, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["ProductVersion": "27.1"], format: .xml, options: 0)
            .write(to: core.appendingPathComponent("SystemVersion.plist"))
        #expect(r.remote.runtimeVersionCommand == "cat '\(core.path)/SystemVersion.plist'")
        #expect(r.remote.readRuntimeVersion() == "27.1")
        #expect(r.log.contains("-o BatchMode=yes tester@fakehost cat"))

        try await withPrefs("probe") { p, dir in
            r.settings.save(p.defaults)
            let wc = try window(try iosApp(in: dir), state: dir.appendingPathComponent("state.json"))
            wc.setDestinationGroups(DestinationCatalog.groups(devices: [], simulators: [sim("iPhone 17", "26.4")]))
            #expect(wc.destinationMenuModel().rows("Simulators").first { $0.isSwiftCodeRemoteSimulator }?.osVersion == nil)
            await wc.refreshRemoteRuntimeVersion(defaults: p.defaults, ssh: r.settings.ssh)?.value
            #expect(RemoteSimulatorSettings.load(p.defaults).runtimeVersion == "27.1")
            #expect(wc.destinationMenuModel().rows("Simulators").first?.isSwiftCodeRemoteSimulator == true)
            #expect(wc.destinationMenuModel().rows("Simulators").first?.osVersion == "27.1")
            #expect(wc.refreshRemoteRuntimeVersion(defaults: p.defaults, ssh: r.settings.ssh) == nil)
        }
    }

    static let eraseLauncher = """
    #!/bin/sh
    echo "launcher args: $*"
    [ "$1" = --erase ] || exit 64
    echo "swiftcode-sim: erased $3"
    """

    @Test func eraseRunsTheLauncherThroughSSH() async throws {
        let r = try makeRemote("erase", launcher: Self.eraseLauncher)
        defer { try? FileManager.default.removeItem(at: r.root) }
        #expect(r.remote.eraseCommand == "exec '\(r.settings.simdPath)' --erase --device '\(r.data.path)/devices/dev1'")
        let s = try session()
        let (ok, message) = await s.eraseRemoteSimulator(remote: r.remote)
        #expect(ok && message == "Erased")
        #expect(r.log.contains("-o BatchMode=yes tester@fakehost exec"))
        #expect(s.consoleText(.debugger).contains("swiftcode-sim: erased \(r.data.path)/devices/dev1"))

        let bad = try makeRemote("erase-bad", launcher: "#!/bin/sh\necho 'swiftcode-sim: --erase needs --device' >&2\nexit 64\n")
        defer { try? FileManager.default.removeItem(at: bad.root) }
        let (ok2, m2) = await s.eraseRemoteSimulator(remote: bad.remote)
        #expect(!ok2 && m2 == "Erase failed (status 64): swiftcode-sim: --erase needs --device")

        #expect(await s.eraseRemoteSimulator(remote: RemoteSimulator(settings: RemoteSimulatorSettings())).0 == false)
        let app = try app(in: r.root)
        s.simulatorRun = SimulatorRunState(target: .remote(destination: "tester@fakehost"), app: try #require(AppBundle(url: app)))
        let (ok3, m3) = await s.eraseRemoteSimulator(remote: r.remote)
        #expect(!ok3 && m3 == "Stop the run on SwiftCode Simulator before erasing it.")
        s.simulatorRun = nil
    }

    @Test func devicesWindowErasesTheRemoteSimulatorAfterConfirmation() async throws {
        let r = try makeRemote("devices", launcher: Self.eraseLauncher, runtimeRoot: "/rr/iOS 27.1")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("devices") { p, dir in
            r.settings.save(p.defaults)
            let wc = try window(try iosApp(in: dir), state: dir.appendingPathComponent("state.json"))
            let other = DeviceRow(name: "Phone A", identifier: "A", platform: "iOS", osVersion: "26.4", state: "Shutdown", model: "Phone A", isAvailable: true)
            let c = DevicesController(devices: [], simulators: [other])
            wc.configureSwiftCodeRemoteDevice(c, defaults: p.defaults, ssh: r.settings.ssh)
            c.view.frame = NSRect(x: 0, y: 0, width: 820, height: 480)
            c.show(.simulators)
            #expect(c.simulators.map(\.name) == ["Phone A", "iPhone Duo (SwiftCode)", "iPad (A16) (SwiftCode)", "iPad Pro 13-inch (M5) (SwiftCode)"])
            let row = try #require(c.simulators.dropFirst().first)
            #expect(row.isSwiftCodeRemote && row.osVersion == "27.1" && row.state == "Shutdown" && row.identifier == "tester@fakehost:\(r.data.path)/devices/dev1")

            #expect(c.contextMenu(forRow: 0).items.isEmpty)
            let menu = c.contextMenu(forRow: 1)
            #expect(menu.items.map(\.title) == ["Start", "", "Open in New Window", "", "Closed", "Partially Open", "Open", "Rotate Left",
                                                "Rotate Right", "", "Erase All Content and Settings…"] && menu.items.last!.isEnabled)
            #expect(menu.items.filter { ["Closed", "Partially Open", "Open", "Rotate Left", "Rotate Right", "Open in New Window"].contains($0.title) }
                .allSatisfy { !$0.isEnabled })

            var asked: [String] = []
            c.confirmErase = { asked.append($0.name); return false }
            #expect(c.erase(row: 1) == nil)
            #expect(asked == ["iPhone Duo (SwiftCode)"] && !r.log.contains("--erase"))
            #expect(c.erase(row: 0) == nil && asked.count == 1)

            c.confirmErase = { _ in true }
            c.select(row: 1)
            let task = try #require(c.erase(row: 1))
            #expect(c.eraseStatus == "Erasing…")
            await task.value
            #expect(c.eraseStatus == "Erased")
            #expect(c.detailRows.contains { $0 == ("Erase", "Erased") })
            #expect(r.log.contains("--erase --device '\(r.data.path)/devices/dev1'"))
            #expect(wc.session.consoleText(.debugger).contains("swiftcode-sim: erased"))
        }
        try await withPrefs("devices-none") { _, dir in
            let wc = try window(try iosApp(in: dir), state: dir.appendingPathComponent("state.json"))
            let c = DevicesController(devices: [], simulators: [])
            wc.configureSwiftCodeRemoteDevice(c)
            #expect(c.simulators.isEmpty)
        }
    }

    static let savingLauncher = """
    #!/bin/sh
    n=0
    trap 'n=$((n+1)); if [ $n -ge 2 ]; then echo "closed"; exit 130; fi; echo "snapshot: exiting after the snapshot"; echo "swiftcode-sim: warm boot: the device was saved; the next run continues from it"' INT
    echo "swiftcode-sim: warm boot: restoring the device"
    echo "launch dev.swiftcode.remote: ok"
    echo "launched dev.swiftcode.remote pid 42"
    echo "hello from the remote app"
    while true; do sleep 0.1; done
    """

    @Test func stopSavesTheDeviceAndClosesWhenTheLauncherReportsIt() async throws {
        let r = try makeRemote("stop", launcher: Self.savingLauncher)
        defer { try? FileManager.default.removeItem(at: r.root) }
        let s = try session()
        await s.runOnRemoteSimulator(app: try app(in: r.root), remote: r.remote)
        #expect(await waitUntil(20) { s.console.contains("hello from the remote app") && s.simulatorRun?.remotePID != nil })
        #expect(s.activity == .running("Running Remote on \(r.remote.destination.name)"))
        #expect(s.consoleText(.debugger).contains("swiftcode-sim: warm boot: restoring the device"))
        #expect(!s.consoleText(.target).contains("swiftcode-sim:") && s.consoleText(.target).contains("hello from the remote app"))
        let pid = try #require(s.simulatorRun?.remotePID)
        s.stopSimulatorRun(remote: r.remote)
        #expect(s.activity == .running("Stopping Remote — saving SwiftCode Simulator…"))
        #expect(await waitUntil(20) { s.simulatorRun == nil })
        #expect(r.log.contains("tester@fakehost kill -INT \(pid)"))
        #expect(s.consoleText(.debugger).contains("swiftcode-sim: warm boot: the device was saved"))
        #expect(s.console.contains("SwiftCode Simulator stopped"))
        #expect(s.activity == .finished("Finished running Remote on \(r.remote.destination.name)"))
    }

    @Test func stopWithWarmBootOffAndWhenTheSignalFails() async throws {
        let r = try makeRemote("stop-fail", launcher: """
        #!/bin/sh
        trap 'echo "stopped by SIGINT"; exit 130' INT
        echo "launched dev.swiftcode.remote pid 42"
        while true; do sleep 0.1; done
        """)
        defer { try? FileManager.default.removeItem(at: r.root) }
        var cold = r.settings
        cold.warmBoot = false
        let remote = RemoteSimulator(settings: cold)
        let s = try session()
        await s.runOnRemoteSimulator(app: try app(in: r.root), remote: remote)
        #expect(await waitUntil(20) { s.console.contains("launched dev.swiftcode.remote") && s.simulatorRun?.remotePID != nil })
        r.touch("fail-kill")
        s.stopSimulatorRun(remote: remote)
        #expect(s.activity == .running("Stopping Remote…"))
        #expect(await waitUntil(20) { s.simulatorRun == nil })
        #expect(s.console.contains("the stop signal did not reach tester@fakehost (ssh status 255)"))
        #expect(s.console.contains("stopped by SIGINT"))
        #expect(s.activity == .finished("Finished running Remote on \(remote.destination.name)"))
    }

    @Test func stopAfterTheGraceTimeAndBeforeThePid() async throws {
        let r = try makeRemote("stop-grace", launcher: """
        #!/bin/sh
        n=0
        trap 'n=$((n+1)); if [ $n -ge 2 ]; then exit 130; fi' INT
        echo "launched dev.swiftcode.remote pid 42"
        while true; do sleep 0.1; done
        """)
        defer { try? FileManager.default.removeItem(at: r.root) }
        var remote = r.remote
        remote.stopGrace = 1
        let s = try session()
        await s.runOnRemoteSimulator(app: try app(in: r.root), remote: remote)
        #expect(await waitUntil(20) { s.console.contains("launched dev.swiftcode.remote") && s.simulatorRun?.remotePID != nil })
        s.stopSimulatorRun(remote: remote)
        #expect(await waitUntil(20) { s.simulatorRun == nil })
        #expect(s.console.contains("did not end 1 s after Stop; closing the connection"))

        r.touch("delay-run")
        await s.runOnRemoteSimulator(app: try app(in: r.root), remote: remote)
        #expect(s.simulatorRun?.remotePID == nil)
        s.stopSimulatorRun(remote: remote)
        #expect(await waitUntil(20) { s.simulatorRun == nil })
        #expect(r.log.components(separatedBy: "tester@fakehost kill -INT").count == 3)
    }

    @Test func secondStopClosesAtOnceAndStopDuringUploadLaunchesNothing() async throws {
        let r = try makeRemote("stop-upload", launcher: Self.savingLauncher, slowRsync: true)
        defer { try? FileManager.default.removeItem(at: r.root) }
        let s = try session()
        let app = try app(in: r.root)
        let run = Task { await s.runOnRemoteSimulator(app: app, remote: r.remote) }
        #expect(await waitUntil(10) { s.simulatorRun != nil })
        s.stopSimulatorRun(remote: r.remote)
        await run.value
        #expect(s.simulatorRun == nil && s.activity == .idle)
        #expect(s.console.contains("stopped before Remote was launched"))
        #expect(!r.log.contains("SWIFTCODE-REMOTE-PID"))

        var slow = r.remote
        slow.stopGrace = 600
        var fast = r.settings
        fast.rsync = "/usr/bin/rsync"
        let remote = RemoteSimulator(settings: fast)
        await s.runOnRemoteSimulator(app: app, remote: remote)
        #expect(await waitUntil(20) { s.console.contains("hello from the remote app") && s.simulatorRun?.remotePID != nil })
        s.stopSimulatorRun(remote: slow)
        s.stopSimulatorRun(remote: slow)
        #expect(await waitUntil(20) { s.simulatorRun == nil })
    }

    @Test func previewFamilyAndActivityText() async throws {
        #expect(WorkspaceWindowController.family(ofDeviceNamed: "iPhone 17 Pro") == "iPhone")
        #expect(WorkspaceWindowController.family(ofDeviceNamed: "iPad Air 13-inch (M3)") == "iPad")
        #expect(WorkspaceWindowController.family(ofDeviceNamed: "Apple Vision Pro") == "Apple Vision")
        #expect(WorkspaceWindowController.family(ofDeviceNamed: "Apple Watch Series 10 (46mm)") == "Apple Watch")
        let sims = [sim("iPhone 17", "26.4"), sim("iPad Air", "27.1"), sim("iPhone 18", "27.1")]
        #expect(WorkspaceWindowController.previewFamily(platform: "iOS", destination: nil, simulators: sims) == "iPhone")
        #expect(WorkspaceWindowController.previewFamily(platform: "iOS", destination: sims[1], simulators: sims) == "iPad")
        #expect(WorkspaceWindowController.previewFamily(platform: "iOS", destination: RemoteSimulator.destination, simulators: sims) == "iPhone")
        #expect(WorkspaceWindowController.previewFamily(platform: "iOS", destination: nil, simulators: []) == "iOS")
        #expect(WorkspaceWindowController.previewFamily(platform: "macOS", destination: nil, simulators: sims) == nil)
        #expect(WorkspaceWindowController.previewFamily(platform: nil, destination: nil, simulators: sims) == nil)

        try await withPrefs("preview") { _, dir in
            let wc = try window(try iosApp(in: dir), state: dir.appendingPathComponent("state.json"))
            wc.setDestinationGroups(DestinationCatalog.groups(devices: [], simulators: sims))
            #expect(wc.previewActivityText == "Preparing iPhone Simulator")
            wc.activityView.status = "Build Succeeded • Today at 10:00"
            let token = wc.beginPreviewActivity()
            #expect(token != nil && wc.activityView.status == "Preparing iPhone Simulator" && wc.activityView.isBusy)
            let newer = wc.beginPreviewActivity()
            wc.endPreviewActivity(token)
            #expect(wc.activityView.status == "Preparing iPhone Simulator")
            wc.endPreviewActivity(newer)
            #expect(wc.activityView.status == "Build Succeeded • Today at 10:00" && !wc.activityView.isBusy)
        }
        let pkg = try WindowSnapshotTests().samplePackage()
        let wc = WorkspaceWindowController(session: WorkspaceSession(model: try WorkspaceModel(url: pkg)), loadDestinations: false,
                                           startLanguageService: false, openFirstFile: false)
        #expect(wc.previewActivityText == nil && wc.beginPreviewActivity() == nil)
    }

    @Test func viewHierarchyAndMemoryGraphAreDisabledPlaceholders() throws {
        _ = NSApplication.shared
        let debug = DebugAreaController()
        _ = debug.view
        for tip in ["Debug View Hierarchy", "Debug Memory Graph"] {
            let b = try #require(debug.barButtonViews.first { $0.toolTip == tip })
            #expect(!b.isEnabled && b.action == nil)
        }
        let backtrace = try #require(debug.barButtonViews.first { $0.toolTip == "Enable Backtrace in Editor" })
        #expect(backtrace.isEnabled)
        let bar = MainMenu.make()
        let item = try #require(bar.item(withTitle: "Debug")?.submenu?.item(withTitle: "View Debugging")?.submenu?.item(withTitle: "Capture View Hierarchy"))
        #expect(item.action != Selector(("debugViewHierarchy:")))
    }
}
