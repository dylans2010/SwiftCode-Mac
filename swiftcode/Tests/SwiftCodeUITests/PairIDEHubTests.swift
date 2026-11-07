import AppKit
import Foundation
import Testing
import SwiftCodeBuild
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized, .timeLimit(.minutes(5))) struct PairIDEHubTests {
    static let iosRoot = "/rr/iOS-27.0-24A434/RuntimeRoot"
    static let watchRoot = "/rr/watchOS-27.0-24R362/RuntimeRoot"

    struct Remote {
        let root: URL
        let settings: RemoteSimulatorSettings
        var log: String { (try? String(contentsOf: root.appendingPathComponent("launcher.log"), encoding: .utf8)) ?? "" }
        var devices: URL { root.appendingPathComponent("data/devices") }
    }

    static let launcher = #"""
    #!/bin/sh
    R="$(dirname "$0")/.."
    echo "$@" >> "$R/launcher.log"
    pairs() { # <id> <watch dir> <phone dir> <state>
      printf '{"pairs":{"%s":{"watch":{"name":"Apple Watch Series 12 (46mm) [%s]","udid":"W1","state":"Shutdown"},"phone":{"name":"iPhone 18 Pro [%s]","udid":"P1","state":"Shutdown"},"state":"%s"}}}\n' "$1" "$2" "$3" "$4" > "$R/listing.json"
    }
    case "$1" in
      pair) w=$(basename "$2"); p=$(basename "$3")
            [ -e "$2/swiftcode-device-type" ] && [ -e "$3/swiftcode-device-type" ] || { echo "swiftcode-simd: no device type" >&2; exit 1; }
            echo "$w $p" > "$R/pair.args"; pairs A14C1055-1F81-4D7B-A25C-710D1D9A7DC1 "$w" "$p" "(inactive, disconnected)"
            echo "swiftcode-sim: note"; echo a14c1055-1f81-4d7b-a25c-710d1d9a7dc1 ;;
      list-pairs) cat "$R/listing.json" 2>/dev/null || echo '{"pairs":{}}' ;;
      pair-activate) set -- $(cat "$R/pair.args"); pairs A14C1055-1F81-4D7B-A25C-710D1D9A7DC1 "$1" "$2" "(active, disconnected)"; echo "swiftcode-simd: pair is active" ;;
      unpair) echo '{"pairs":{}}' > "$R/listing.json"; echo "erased /x/watch" ;;
      --erase) rm -rf "$3"; echo "erased $3" ;;
      *) echo "error: unknown"; exit 64 ;;
    esac
    """#

    func makeRemote(_ tag: String) throws -> Remote {
        let root = swiftcodeDir.appendingPathComponent(".build-ide/pair-ide-\(tag)-\(UUID().uuidString.prefix(8))")
        let ssh = root.appendingPathComponent("bin/fake-ssh")
        try writeExecutable("""
        #!/bin/sh
        while [ $# -gt 0 ]; do
          case "$1" in
            -o) shift 2 ;;
            -*) shift ;;
            *) break ;;
          esac
        done
        shift
        exec /bin/sh -c "$*"
        """, ssh)
        let simd = root.appendingPathComponent("bin/swiftcode-sim")
        try writeExecutable(Self.launcher, simd)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("data/devices"), withIntermediateDirectories: true)
        var s = RemoteSimulatorSettings(destination: "tester@fakehost", dataDirectory: root.appendingPathComponent("data").path,
                                        runtimeRoot: Self.iosRoot, simdPath: simd.path, deviceName: "dev", ssh: ssh.path)
        s.otherRuntimeRoots = [Self.watchRoot]
        s.runtimeVersion = "27.0"
        return Remote(root: root, settings: s)
    }

    func withPrefs(_ tag: String, _ body: (Preferences, URL) async throws -> Void) async throws {
        let t = TestDefaults("pair-ide-\(tag)")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-pair-ide-\(tag)-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Preferences(defaults: t.defaults, themesDirectory: dir.appendingPathComponent("Themes"))
        let old = Preferences.shared, oldStore = RemotePairsStore.shared.defaults
        Preferences.shared = p
        RemotePairsStore.shared.defaults = t.defaults
        defer {
            Preferences.shared = old
            RemotePairsStore.shared.defaults = oldStore
            NotificationCenter.default.post(name: Preferences.didChange, object: nil)
            t.remove()
            try? FileManager.default.removeItem(at: dir)
        }
        try await body(p, dir)
    }

    func save(_ r: Remote, _ d: UserDefaults) {
        r.settings.save(d)
        RemoteSimulatorSettings.saveRuntimeVersion("27.0", root: Self.iosRoot, d)
        RemoteSimulatorSettings.saveRuntimeVersion("27.0", root: Self.watchRoot, d, primary: false)
        RemoteSimulatorSettings.saveRuntimePlatform("iOS", root: Self.iosRoot, d)
        RemoteSimulatorSettings.saveRuntimePlatform("watchOS", root: Self.watchRoot, d)
    }

    func window(_ dir: URL, project: URL? = nil) throws -> WorkspaceWindowController {
        _ = NSApplication.shared
        let url = try project ?? WindowSnapshotTests().samplePackage()
        return WorkspaceWindowController(session: WorkspaceSession(model: try WorkspaceModel(url: url)), loadDestinations: false,
                                         startLanguageService: false, openFirstFile: false, userStateURL: dir.appendingPathComponent("state.json"))
    }

    func hub(_ wc: WorkspaceWindowController, _ r: Remote, _ p: Preferences) -> DevicesController {
        let c = DevicesController(devices: [], simulators: [])
        wc.configureSwiftCodeRemoteDevice(c, defaults: p.defaults, ssh: r.settings.ssh)
        c.view.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
        c.pairing.confirm = { _, _, _ in true }
        return c
    }

    func index(_ c: DevicesController, _ name: String) -> Int? { c.rows.firstIndex { $0.name == name } }

    @Test func theHubShowsPairsOnThePhoneAndTheWatch() async throws {
        let r = try makeRemote("show")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("show") { p, dir in
            save(r, p.defaults)
            let wc = try window(dir)
            let c = hub(wc, r, p)
            let s = RemoteSimulatorSettings.load(p.defaults)
            let phone = try #require(s.targets.first), watch = try #require(s.watchTargets.first), other = s.watchTargets[1]
            c.setPairs([RemoteDevicePair(id: "P1", watchDirectory: watch.deviceDirectoryName, phoneDirectory: phone.deviceDirectoryName,
                                         watchTypeName: "Apple Watch Series 12 (46mm)", phoneTypeName: "iPhone 18 Pro", active: true, connected: true),
                        RemoteDevicePair(id: "P2", watchDirectory: other.deviceDirectoryName, phoneDirectory: phone.deviceDirectoryName, active: false)])
            c.select(row: try #require(index(c, "iPhone 18 Pro (SwiftCode)")))
            #expect(c.canvas.pairedTitle == "Paired with Apple Watch Series 12 (46mm) (SwiftCode)")
            #expect(c.canvas.pairedCapsule != nil)
            let rows = Dictionary(c.detailRows, uniquingKeysWith: { a, _ in a })
            #expect(rows["Active Watch"] == "Apple Watch Series 12 (46mm) (SwiftCode)")
            #expect(rows["Paired Watches"] == "Apple Watch Series 12 (46mm) (SwiftCode) (active), Apple Watch Series 12 (42mm) (SwiftCode)")
            #expect(rows["Pair"] == "(active, connected)")
            let titles = c.contextMenu(forRow: try #require(index(c, "iPhone 18 Pro (SwiftCode)"))).items.map(\.title)
            #expect(titles.contains("Pair Watch…"))
            #expect(titles.contains("Unpair “Apple Watch Series 12 (46mm) (SwiftCode)”") && titles.contains("Unpair “Apple Watch Series 12 (42mm) (SwiftCode)”"))
            #expect(titles.contains("Make “Apple Watch Series 12 (42mm) (SwiftCode)” Active") && !titles.contains("Make “Apple Watch Series 12 (46mm) (SwiftCode)” Active"))
            c.canvas.onPaired?()
            #expect(c.selected?.name == "Apple Watch Series 12 (46mm) (SwiftCode)")
            #expect(c.canvas.pairedTitle == "Paired with iPhone 18 Pro (SwiftCode)")
            let w = Dictionary(c.detailRows, uniquingKeysWith: { a, _ in a })
            #expect(w["Paired With"] == "iPhone 18 Pro (SwiftCode)" && w["Pair"] == "(active, connected)")
            #expect(c.contextMenu(forRow: try #require(index(c, "Apple Watch Series 12 (46mm) (SwiftCode)"))).items.map(\.title).contains("Unpair from “iPhone 18 Pro (SwiftCode)”"))
            c.select(row: try #require(index(c, "Apple Watch Ultra 4 (49mm) (SwiftCode)")))
            #expect(c.canvas.pairedTitle == nil)
            #expect(Dictionary(c.detailRows, uniquingKeysWith: { a, _ in a })["Paired With"] == "None")
            let add = DeviceHubToolbar.addItems(target: nil, hub: c)
            #expect(add.map(\.title) == ["iPhone…", "iPad…", "Apple Watch…", "iPhone with Paired Watch…", "Apple Vision Pro…", "Apple TV…", "", "Pair Nearby Device…"])
            #expect(add[2].isEnabled && add[3].isEnabled && !add[4].isEnabled)
        }
    }

    @Test func noWatchRuntimeMeansNoPairingItems() async throws {
        let r = try makeRemote("none")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("none") { p, dir in
            var s = r.settings
            s.otherRuntimeRoots = []
            s.save(p.defaults)
            let wc = try window(dir)
            let c = hub(wc, r, p)
            let i = try #require(c.rows.firstIndex { $0.isSwiftCodeRemote })
            c.select(row: i)
            #expect(!c.contextMenu(forRow: i).items.map(\.title).contains("Pair Watch…"))
            #expect(!c.detailRows.contains { $0.0 == "Active Watch" })
            #expect(!DeviceHubToolbar.addItems(target: nil, hub: c)[2].isEnabled)
        }
    }

    @Test func pairWatchPairsAnExistingWatchThroughTheLauncher() async throws {
        let r = try makeRemote("pair")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("pair") { p, dir in
            save(r, p.defaults)
            let wc = try window(dir)
            let c = hub(wc, r, p)
            let phone = try #require(c.rows.first { $0.name == "iPhone 18 Pro (SwiftCode)" })
            var forms: [HubDeviceForm] = []
            c.pairing.presentForm = { form, done in
                forms.append(form)
                form.chooseWatch("Apple Watch Ultra 4 (49mm) (SwiftCode)")
                done(true)
            }
            c.presentPairWatch(phone: phone)
            let form = try #require(forms.first)
            #expect(form.kind == .pairWatch && form.title == "Pair a Watch with “iPhone 18 Pro (SwiftCode)”" && form.button == "Pair")
            #expect(form.watchPopUp.itemTitles.last == HubDeviceForm.newWatchTitle)
            #expect(form.watchPopUp.itemTitles.contains("Apple Watch Series 12 (46mm) (SwiftCode)"))
            #expect(form.chosenWatch?.name == "Apple Watch Ultra 4 (49mm) (SwiftCode)" && form.watch?.name.isEnabled == false)
            await c.pairing.task?.value
            let s = RemoteSimulatorSettings.load(p.defaults)
            let watchDir = try #require(s.watchTargets.first { $0.deviceType.id == "apple-watch-ultra-4-49mm" }).deviceDirectoryName
            let phoneDir = try #require(s.targets.first).deviceDirectoryName
            #expect(r.log.contains("pair \(r.devices.path)/\(watchDir) \(r.devices.path)/\(phoneDir)"), "\(r.log)")
            #expect((try? String(contentsOf: r.devices.appendingPathComponent("\(watchDir)/swiftcode-device-type"), encoding: .utf8)) == "apple-watch-ultra-4-49mm\n")
            #expect(r.log.contains("list-pairs --json"))
            #expect(c.pairing.status == "Paired (A14C1055-1F81-4D7B-A25C-710D1D9A7DC1)")
            #expect(c.pairing.pairs.map(\.watchDirectory) == [watchDir])
            #expect(RemotePairsStore.shared.current().count == 1, "the destinations read the same pairs")
            c.select(row: try #require(index(c, "iPhone 18 Pro (SwiftCode)")))
            #expect(c.canvas.pairedTitle == nil, "no active watch yet")
            let pair = try #require(c.pairing.pairs.first)
            c.activate(pair)
            await c.pairing.task?.value
            #expect(r.log.contains("pair-activate \(pair.id)"))
            #expect(c.pairing.pairs.first?.active == true && c.pairing.status == "Active")
            #expect(c.canvas.pairedTitle == "Paired with Apple Watch Ultra 4 (49mm) (SwiftCode)")
            var asked: [String] = []
            c.pairing.confirm = { title, _, button in asked.append("\(title)|\(button)"); return true }
            c.unpair(try #require(c.pairing.pairs.first))
            await c.pairing.task?.value
            #expect(asked == ["Unpair “Apple Watch Ultra 4 (49mm) (SwiftCode)” from “iPhone 18 Pro (SwiftCode)”?|Unpair"])
            #expect(r.log.contains("unpair A14C1055-1F81-4D7B-A25C-710D1D9A7DC1"))
            #expect(c.pairing.pairs.isEmpty && c.pairing.status == "Unpaired; the watch was erased")
            #expect(c.canvas.pairedTitle == nil)
        }
    }

    @Test func makeActiveOffersToRestartARunningIPhone() async throws {
        let r = try makeRemote("restart")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("restart") { p, dir in
            save(r, p.defaults)
            let wc = try window(dir)
            let c = hub(wc, r, p)
            c.currentRemoteRows = nil
            let s = RemoteSimulatorSettings.load(p.defaults)
            let phone = try #require(s.targets.first), a = try #require(s.watchTargets.first), b = s.watchTargets[1]
            func pairs(activeB: Bool) -> [RemoteDevicePair] {
                [RemoteDevicePair(id: "PA", watchDirectory: a.deviceDirectoryName, phoneDirectory: phone.deviceDirectoryName, active: !activeB),
                 RemoteDevicePair(id: "PB", watchDirectory: b.deviceDirectoryName, phoneDirectory: phone.deviceDirectoryName, active: activeB)]
            }
            c.setPairs(pairs(activeB: false))
            var activeB = false
            c.pairing.activatePair = { _ in activeB.toggle(); return (true, "Active") }
            c.pairing.readPairs = { pairs(activeB: activeB) }
            var lifecycle: [String] = []
            c.startDevice = { row in lifecycle.append("start \(row.name)"); return (true, "Started") }
            c.shutDownDevice = { row, _ in lifecycle.append("shut down \(row.name)"); return (true, "Shut down") }
            var offers: [String] = []
            var answer = false
            c.pairing.offerPhoneRestart = { title, text in offers.append(title + "|" + text); return answer }
            c.activate(try #require(c.pairing.pairs.first { $0.id == "PB" }))
            await c.pairing.task?.value
            #expect(offers.isEmpty && c.pairing.status == "Active" && c.pairing.restartTask == nil)
            var row = try #require(c.rows.first { $0.name == "iPhone 18 Pro (SwiftCode)" })
            row.state = "Booted"
            c.updateSwiftCodeRemote(row)
            c.activate(try #require(c.pairing.pairs.first { $0.id == "PA" }))
            await c.pairing.task?.value
            #expect(offers == ["“Apple Watch Series 12 (46mm) (SwiftCode)” is now the active watch of “iPhone 18 Pro (SwiftCode)”."
                               + "|Apps on the iPhone keep using the previous watch until the iPhone restarts. "
                               + "Restart the iPhone now to connect its apps to “Apple Watch Series 12 (46mm) (SwiftCode)”."])
            #expect(c.pairing.status == "Active; apps on the iPhone keep the previous watch until the iPhone restarts")
            #expect(lifecycle.isEmpty && c.pairing.restartTask == nil)
            #expect(Dictionary(c.detailRows, uniquingKeysWith: { x, _ in x })["Pairing"] == c.pairing.status)
            answer = true
            c.activate(try #require(c.pairing.pairs.first { $0.id == "PB" }))
            await c.pairing.task?.value
            #expect(offers.count == 2 && offers[1].hasPrefix("“Apple Watch Series 12 (42mm) (SwiftCode)” is now the active watch"))
            await c.pairing.restartTask?.value
            #expect(lifecycle == ["shut down iPhone 18 Pro (SwiftCode)", "start iPhone 18 Pro (SwiftCode)"])
            #expect(c.pairing.status == "Active; restarting the iPhone")
            #expect(HubPairing.restartPhoneButton == "Restart iPhone")
        }
    }

    @Test func anIPhoneWithAPairedWatchIsCreatedInOneStep() async throws {
        let r = try makeRemote("create")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("create") { p, dir in
            save(r, p.defaults)
            let wc = try window(dir)
            let c = hub(wc, r, p)
            var shown: HubDeviceForm?
            c.pairing.presentForm = { form, done in
                shown = form
                form.phone?.name.stringValue = "Test Phone"
                form.watch?.name.stringValue = "Test Watch"
                form.watch?.selectModel("Apple Watch Series 12 (46mm)")
                done(true)
            }
            c.presentNewPairedPhone()
            let form = try #require(shown)
            #expect(form.kind == .newPairedPhone && form.phone?.os.itemTitles == ["iOS 27.0"] && form.watch?.os.itemTitles == ["watchOS 27.0"])
            #expect(form.phone?.model.itemTitles == ["iPhone 18 Pro"])
            #expect(form.watch?.model.itemTitles.first == "Apple Watch Series 12 (46mm)")
            await c.pairing.task?.value
            let created = RemoteSimulatorSettings.createdDevices(p.defaults)
            #expect(created.map(\.name) == ["Test Phone", "Test Watch"])
            #expect(created.map(\.typeID) == ["iphone-18-pro", "apple-watch-series-12-46mm"])
            #expect(created.map(\.runtimeRoot) == [Self.iosRoot, Self.watchRoot])
            #expect(c.rows.contains { $0.name == "Test Phone" && $0.isCreated } && c.rows.contains { $0.name == "Test Watch" && $0.platform == "watchOS" })
            #expect(c.selected?.name == "Test Phone")
            #expect(r.log.contains("pair \(r.devices.path)/\(created[1].directoryName) \(r.devices.path)/\(created[0].directoryName)"), "\(r.log)")
            #expect(c.pairing.pairs.first?.phoneDirectory == created[0].directoryName)
            let phone = try #require(c.rows.first { $0.name == "Test Phone" })
            #expect(c.pairingMenuItems(for: phone).map(\.title).contains("Delete…"))
            #expect(c.delete(phone) == nil)
            #expect(c.pairing.status == "Unpair “Test Phone” before deleting it.")
            c.unpair(try #require(c.pairing.pairs.first))
            await c.pairing.task?.value
            c.delete(phone)
            await c.pairing.task?.value
            #expect(r.log.contains("--erase --device \(r.devices.path)/\(created[0].directoryName)"))
            #expect(RemoteSimulatorSettings.createdDevices(p.defaults).map(\.name) == ["Test Watch"])
            #expect(!c.rows.contains { $0.name == "Test Phone" })
            c.pairing.presentForm = { form, done in form.watch?.name.stringValue = "Second Watch"; done(true) }
            let w = c.presentNewWatch()
            #expect(w.kind == .newWatch && w.button == "Create")
            #expect(c.selected?.name == "Second Watch")
        }
    }

    @Test func watchSchemesListWatchesAndPhonesWithAnActiveWatch() async throws {
        let r = try makeRemote("dest")
        defer { try? FileManager.default.removeItem(at: r.root) }
        try await withPrefs("dest") { p, dir in
            save(r, p.defaults)
            let s = RemoteSimulatorSettings.load(p.defaults)
            RemotePairsStore.shared.set([RemoteDevicePair(id: "P1", watchDirectory: s.watchTargets[0].deviceDirectoryName,
                                                          phoneDirectory: s.targets[0].deviceDirectoryName, active: true)])
            let wc = try window(dir, project: swiftcodeDir.appendingPathComponent("Samples/WatchSamples/WatchSamples.xcodeproj"))
            wc.setDestinationGroups([])
            wc.session.scheme = "WCProbeWatch"
            let watchMenu = wc.destinationMenuModel()
            let sims = watchMenu.rows("Simulators")
            #expect(sims.contains { $0.isSwiftCodePairedDestination && $0.name == "iPhone 18 Pro (SwiftCode) with Apple Watch Series 12 (46mm) (SwiftCode)" })
            #expect(sims.contains { $0.name == "Apple Watch Series 12 (46mm) (SwiftCode)" })
            #expect(sims.allSatisfy { $0.platform == "watchOS" })
            #expect(wc.productPlatform.platform == "watchOS" && wc.productPlatform.deploymentTarget == "27.0")
            wc.session.scheme = "WCProbe"
            let iosMenu = wc.destinationMenuModel()
            #expect(iosMenu.rows("Simulators").allSatisfy { $0.platform == "iOS" })
            #expect(iosMenu.incompatible.contains { $0.name.hasPrefix("Apple Watch Series 12 (46mm) (SwiftCode)") })
            #expect(WorkspaceWindowController.remoteProductPath(fromExecutablePath: "/dd/Build/Products/Debug/WCProbeWatch.app/Contents/MacOS/WCProbeWatch", watch: true)
                == "/dd/Build/Products/Debug-watchsimulator/WCProbeWatch.app")
            #expect(WorkspaceWindowController.remoteProductPath(fromExecutablePath: "/dd/Build/Products/Debug/WCProbe.app/Contents/MacOS/WCProbe", watch: false)
                == "/dd/Build/Products/Debug-iphonesimulator/WCProbe.app")
            wc.session.scheme = "WCProbeWatch"
            wc.session.destination = sims.first { $0.isSwiftCodePairedDestination }
            WorkspaceWindowController.remoteSSHOverride = r.settings.ssh
            defer { WorkspaceWindowController.remoteSSHOverride = nil }
            wc.runProduct(nil)
            #expect(await waitUntil(20) { wc.session.activity == .finished("Run failed") })
            #expect(wc.session.console.contains("The install is directed to a paired Apple Watch, but there isn't one. Select an iPhone Run Destination with a paired Apple Watch."))
            #expect(wc.lastRunAlert?.0 == RemoteWatchRunError.noPairedWatch)
            #expect(RemotePairsStore.shared.current().isEmpty, "the run read the host's pairs first")
        }
    }
}
