import Foundation
import Testing
@testable import YcodeIDECore

@Suite struct RuntimeSetupTests {
    typealias R = StandInRunner

    static let images = """
    {"A1":{"build":"24A434","deletable":true,"identifier":"A1","kind":"Patchable Cryptex Disk Image","platformIdentifier":"com.apple.platform.iphonesimulator",
    "runtimeBundlePath":"/Volumes/iOS_24A434/Runtimes/iOS 27.0.simruntime","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0",
    "signatureState":"Verified","sizeBytes":7873719649,"state":"Ready","supportedArchitectures":["arm64"],"version":"27.0","lastUsedAt":"2026-11-01T10:00:00Z"},
    "B2":{"build":"24A94401","identifier":"B2","platformIdentifier":"com.apple.platform.iphonesimulator","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-1",
    "sizeBytes":8067000161,"state":"Ready","supportedArchitectures":["arm64"],"version":"27.1"},
    "C3":{"build":"24M362","identifier":"C3","platformIdentifier":"com.apple.platform.xrsimulator","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.xrOS-27-0",
    "sizeBytes":7300000000,"state":"Unusable","supportedArchitectures":["arm64"],"version":"27.0"}}
    """

    static let runtimes = """
    {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","buildversion":"24A434","version":"27.0","platform":"iOS","isAvailable":true,
    "runtimeRoot":"/Volumes/iOS_24A434/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot","lastUsage":{"arm64":"0001-01-01T00:00:00Z"}},
    {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-1","buildversion":"24A94401","version":"27.1","platform":"iOS","isAvailable":false,
    "availabilityError":"runtime profile not found"},
    {"identifier":"com.apple.CoreSimulator.SimRuntime.watchOS-26-5","buildversion":"23T570","version":"26.5","platform":"watchOS","isAvailable":true}]}
    """

    static func plist(_ d: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0)
    }

    static let systemVersion = plist(["ProductName": "iPhone OS", "ProductVersion": "27.0", "ProductBuildVersion": "24A434"])

    static func fakeBundle(in dir: URL, name: String = "iOS 27.0.simruntime", product: String = "iPhone OS", version: String = "27.0",
                           build: String = "24A434", platformID: String = "com.apple.platform.iphonesimulator") throws -> URL {
        let b = dir.appendingPathComponent(name)
        let fm = FileManager.default
        let root = b.appendingPathComponent("Contents/Resources/RuntimeRoot")
        try fm.createDirectory(at: root.appendingPathComponent("System/Library/CoreServices"), withIntermediateDirectories: true)
        try plist(["CFBundleIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0", "CFBundleName": "iOS 27.0"])
            .write(to: b.appendingPathComponent("Contents/Info.plist"))
        try plist(["defaultVersionString": version, "platformIdentifier": platformID, "supportedArchs": ["arm64"]])
            .write(to: b.appendingPathComponent("Contents/Resources/profile.plist"))
        try plist(["ProductName": product, "ProductVersion": version, "ProductBuildVersion": build])
            .write(to: root.appendingPathComponent("System/Library/CoreServices/SystemVersion.plist"))
        try fm.createDirectory(at: root.appendingPathComponent("usr/lib"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 4096).write(to: root.appendingPathComponent("usr/lib/libfake.dylib"))
        return b
    }

    static func temp() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-runtime-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static let mac = SetupMachine(isMac: true, architecture: "arm64")
    static let arm = SetupMachine(isMac: false, architecture: "aarch64")
    static let x86 = SetupMachine(isMac: false, architecture: "x86_64")

    @Test func platformsFromEverySpelling() {
        #expect(SimPlatform(name: "iPhone OS") == .iOS)
        #expect(SimPlatform(name: "Watch OS") == .watchOS)
        #expect(SimPlatform(name: "xrOS") == .visionOS)
        #expect(SimPlatform(name: "com.apple.CoreSimulator.SimRuntime.tvOS-27-0") == .tvOS)
        #expect(SimPlatform(name: "macOS") == nil)
        #expect(SimPlatform.visionOS.runtimeToken == "xrOS")
    }

    @Test func sizesAsSimctlPrintsThem() {
        #expect(RuntimeSize.format(7_873_719_649) == "7.3 GB")
        #expect(RuntimeSize.format(512) == "512 bytes")
        #expect(RuntimeSize.format(1536) == "1.5 KB")
    }

    @Test func listingsJoinOnIdentifierAndBuild() {
        let list = SimctlRuntimeListing.parse(images: Data(Self.images.utf8), runtimes: Data(Self.runtimes.utf8))
        #expect(list.map(\.title) == ["iOS 27.1 (24A94401)", "iOS 27.0 (24A434)", "watchOS 26.5 (23T570)", "visionOS 27.0 (24M362)"])
        let ios27 = list[1]
        #expect(ios27.sizeText == "7.3 GB" && ios27.isUsable && ios27.imageUUID == "A1" && ios27.lastUsed == "2026-11-01T10:00:00Z")
        #expect(ios27.runtimeRoot?.hasSuffix("iOS 27.0.simruntime/Contents/Resources/RuntimeRoot") == true)
        #expect(!list[0].isUsable && list[0].availabilityError == "runtime profile not found")
        #expect(!list[3].isUsable)
        #expect(!list.contains { $0.isRemovable })
    }

    @Test func fakeBundleIsReadFromItsPropertyLists() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let b = try Self.fakeBundle(in: dir)
        #expect(RuntimeBundleReader.kind(of: b.path) == .bundle)
        #expect(RuntimeBundleReader.kind(of: b.path + "/Contents/Resources/RuntimeRoot") == .runtimeRoot)
        #expect(RuntimeBundleReader.kind(of: dir.path + "/iOS 27.0 Simulator Runtime.dmg") == .diskImage)
        #expect(RuntimeBundleReader.kind(of: dir.path) == .unknown)
        let r = try #require(RuntimeBundleReader.read(b.path, measure: true))
        #expect(r.title == "iOS 27.0 (24A434)" && r.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        #expect(r.unpackedBytes ?? 0 >= 4096)
        #expect(r.folderName == "iOS-27.0-24A434")
        let vision = try Self.fakeBundle(in: dir, name: "xrOS 27.0.simruntime", product: "xrOS", build: "24M362", platformID: "com.apple.platform.xrsimulator")
        #expect(RuntimeBundleReader.read(vision.path)?.platform == .visionOS)
    }

    @Test func copyIntoSwiftCodesFolderThenListThenRemove() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let b = try Self.fakeBundle(in: dir)
        let r = try #require(RuntimeBundleReader.read(b.path, measure: true))
        let folder = dir.appendingPathComponent("runtimes").path
        let copy = RuntimeCommands.copyLocal(source: r.runtimeRoot!, folder: folder, record: r, markerJSON: RuntimeMarker(r, source: "test").json)
        #expect(shell(copy) == 0)
        let listed = RuntimeBundleReader.swiftcodeRuntimes(in: folder)
        #expect(listed.map(\.title) == ["iOS 27.0 (24A434)"])
        #expect(listed[0].isRemovable && listed[0].owner == .swiftcode(folder: folder + "/iOS-27.0-24A434"))
        #expect(shell(copy) == 0)
        #expect(RuntimeBundleReader.swiftcodeRuntimes(in: folder).count == 1)
        #expect(RuntimeCommands.remove(path: folder, folder: folder) == nil)
        #expect(RuntimeCommands.remove(path: "/", folder: folder) == nil)
        #expect(RuntimeCommands.remove(path: folder + "/../x", folder: folder) == nil)
        #expect(RuntimeCommands.remove(path: dir.path + "/runtimes-other/x", folder: folder) == nil)
        let rm = try #require(RuntimeCommands.remove(path: folder + "/iOS-27.0-24A434", folder: folder))
        #expect(shell(rm) == 0)
        #expect(RuntimeBundleReader.swiftcodeRuntimes(in: folder).isEmpty)
        #expect(FileManager.default.fileExists(atPath: b.path))
    }

    func shell(_ cmd: String) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    static var macReady: [(String, HeadsetCommandResult)] {
        [("xcrun --find simctl", R.ok("/Applications/Xcode.app/Contents/Developer/usr/bin/simctl\n")),
         ("simctl runtime list -j", R.ok(images)), ("simctl list runtimes -j", R.ok(runtimes)),
         ("df -Pk", R.ok("209715200\n"))]
    }

    func choices(_ ps: Set<SimPlatform>, host: Bool = false) -> RuntimeSetupChoices {
        var c = RuntimeSetupChoices()
        c.platforms = ps
        c.useHost = host
        return c
    }

    @Test func macWithXcodesRuntimes() async {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let r = await RuntimeSetupChecker(machine: Self.mac, choices: choices([.iOS, .visionOS, .tvOS]), runner: R(answers: Self.macReady), folder: dir.path).run()
        #expect(r.check("machine")?.state == .ok)
        #expect(r.check("tools")?.state == .ok)
        let ios = r.check("runtime.iOS")
        #expect(ios?.state == .ok && ios?.reason == "iOS 27.0 (24A434), 7.3 GB.")
        let vision = r.check("runtime.visionOS")
        #expect(vision?.state == .missing && vision?.reason.contains("cannot be used") == true)
        if case .instructions = vision?.fix {} else { Issue.record("expected instructions, got \(String(describing: vision?.fix))") }
        let tv = r.check("runtime.tvOS")
        #expect(tv?.state == .missing && tv?.fix == .step(.download))
        #expect(r.check("disk")?.state == .ok)
        #expect(r.readyPlatforms == [.iOS])
        #expect(r.firstProblemStep(for: .thisMachine) == .runtimes)
        #expect(r.state(of: .target) == .ok)
    }

    @Test func deploymentTargetAboveEveryRuntime() async {
        var c = choices([.iOS])
        c.minimumVersions[.iOS] = "28.0"
        let r = await RuntimeSetupChecker(machine: Self.mac, choices: c, runner: R(answers: Self.macReady), folder: "/nonexistent").run()
        #expect(r.check("runtime.iOS")?.state == .missing)
        #expect(r.check("runtime.iOS")?.reason.contains("older than the deployment target 28.0") == true)
    }

    @Test func noXcodeAndLowDiskThenRetry() async {
        let runner = R(answers: [("df -Pk", R.ok("1048576\n"))])
        let r = await RuntimeSetupChecker(machine: Self.mac, choices: choices([.iOS]), runner: runner, folder: "/nonexistent").run()
        #expect(r.check("tools")?.state == .missing && r.check("tools")?.fix == .command("xcodebuild -runFirstLaunch"))
        #expect(r.check("runtime.iOS")?.state == .missing)
        #expect(r.check("disk")?.state == .missing && r.check("disk")?.reason.hasPrefix("1.0 GB free") == true)
        let again = await RuntimeSetupChecker(machine: Self.mac, choices: choices([.iOS]), runner: R(answers: Self.macReady), folder: "/nonexistent").run()
        #expect(again.check("tools")?.state == .ok && again.check("runtime.iOS")?.state == .ok)
        let unreadable = await RuntimeSetupChecker(machine: Self.mac, choices: choices([.iOS]), runner: R(answers: []), folder: "/nonexistent").run()
        #expect(unreadable.check("disk")?.state == .unknown)
    }

    @Test func linuxMachines() async throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let x = await RuntimeSetupChecker(machine: Self.x86, choices: choices([.iOS]), runner: R(answers: []), folder: dir.path).run()
        #expect(x.check("machine")?.state == .missing && x.check("machine")?.fix == .step(.host))
        let b = try Self.fakeBundle(in: dir)
        let rec = try #require(RuntimeBundleReader.read(b.path))
        let folder = dir.appendingPathComponent("rt").path
        _ = shell(RuntimeCommands.copyLocal(source: rec.runtimeRoot!, folder: folder, record: rec, markerJSON: RuntimeMarker(rec, source: "t").json))
        let a = await RuntimeSetupChecker(machine: Self.arm, choices: choices([.iOS]), runner: R(answers: [("/dev/kvm", R.ok("denied\n")), ("df -Pk", R.ok("99999999\n"))]),
                                          folder: folder).run()
        #expect(a.check("kvm")?.state == .missing && a.check("kvm")?.fix == .command("sudo usermod -aG kvm $USER"))
        #expect(a.check("runtime.iOS")?.state == .ok)
        #expect(a.local.first?.isRemovable == true)
        #expect(a.check("tools") == nil)
    }

    @Test func stepsPerTarget() {
        #expect(RuntimeSetupStep.steps(for: .thisMachine) == [.target, .runtimes, .download, .add, .finish])
        #expect(RuntimeSetupStep.steps(for: .host(RuntimeHostSettings())) == [.target, .host, .prepare, .runtimes, .download, .add, .finish])
        #expect(RuntimeSetupChecker.acquisitionNote(.visionOS).contains("xcodebuild -downloadPlatform visionOS"))
        #expect(RuntimeImportTool.simctl.command(file: "/tmp/iOS 27.dmg") == ["xcrun", "simctl", "runtime", "add", "/tmp/iOS 27.dmg"])
        #expect(RuntimeImportTool.xcodebuild.command(file: "/tmp/a.dmg") == ["xcodebuild", "-importPlatform", "/tmp/a.dmg"])
    }

    static let host = RuntimeHostSettings(destination: "tester@sim-host", dataDirectory: "/data/swiftcode")

    static func listing(marker: Bool) -> String {
        let sv = systemVersion.base64EncodedString()
        let m = Data(#"{"platform":"iOS","version":"27.0","build":"24A434","source":"t","copiedAt":"x","sizeBytes":17179869184}"#.utf8).base64EncodedString()
        return "RT\t/data/swiftcode/runtimes/iOS-27.0-24A434\t-\t\(sv)\t\(marker ? m : "-")\nRT\t/rt/iOS-27.0/RuntimeRoot\t1024\t\(sv)\t-\nIN\t/data/swiftcode/runtimes/xrOS-27.0-24M362.incoming\t2048\n"
    }

    static var hostReady: [(String, HeadsetCommandResult)] {
        [("uname -sm", R.ok("Linux aarch64\n")), ("/dev/kvm", R.ok("access\n")), ("--version", R.ok("swiftcode 1.0.0-beta.2 (abc)\n")),
         ("b64()", R.ok(listing(marker: true))), ("df -Pk", R.ok("524288000\n"))]
    }

    @Test func hostReadyWithARuntimeAndAStoppedCopy() async {
        let c = RuntimeHostChecker(host: Self.host, choices: choices([.iOS, .visionOS], host: true), runner: R(answers: Self.hostReady),
                                   pairedHosts: ["sim-host"], localVersion: "1.0.0-beta.2")
        let r = await c.run()
        for id in ["host.reach", "host.link", "host.platform", "host.kvm", "host.version", "host.disk", "host.runtime.iOS"] {
            #expect(r.check(id)?.state == .ok, "\(id): \(r.check(id)?.reason ?? "none")")
        }
        #expect(r.check("host.runtime.visionOS")?.state == .missing)
        #expect(r.check("transfer")?.reason.contains("stopped after 2.0 MB") == true)
        #expect(r.host.count == 2)
        #expect(r.host.filter(\.isRemovable).map(\.runtimeRoot) == ["/data/swiftcode/runtimes/iOS-27.0-24A434/RuntimeRoot"])
        #expect(r.host.first { !$0.isRemovable }?.owner == .external)
        #expect(r.host[0].unpackedBytes == 17_179_869_184)
    }

    @Test func offlineHostIsUnknownNotMissing() async {
        let r = await RuntimeHostChecker(host: Self.host, choices: choices([.iOS], host: true), runner: R(answers: [])).run()
        #expect(r.check("host.reach")?.state == .unknown && r.check("host.reach")?.reason.contains("offline") == true)
        #expect(r.checks.allSatisfy { $0.state == .unknown })
        #expect(r.check("host.runtime.iOS")?.reason == "The host is offline.")
        let none = await RuntimeHostChecker(host: RuntimeHostSettings(), choices: choices([.iOS], host: true), runner: R(answers: [])).run()
        #expect(none.check("host.reach")?.state == .missing)
    }

    @Test func wrongHostVersionLinkAndPlatform() async {
        var answers = Self.hostReady
        answers[0] = ("uname -sm", R.ok("Linux x86_64\n"))
        answers[2] = ("--version", R.ok("swiftcode 1.0.0-beta.1\n"))
        let r = await RuntimeHostChecker(host: Self.host, choices: choices([.iOS], host: true), runner: R(answers: answers), localVersion: "1.0.0-beta.2").run()
        #expect(r.check("host.platform")?.state == .missing)
        #expect(r.check("host.version")?.reason == "The host has 1.0.0-beta.1, this machine 1.0.0-beta.2. Prepare Host installs SwiftCode 1.0.0-beta.2 there.")
        #expect(r.check("host.link")?.fix == .command("swiftcode sim remote pair sim-host <code> --name sim-host"))
        #expect(RuntimeHostChecker.version(inVersionOutput: "swiftcode 1.0.0-beta.1 (117f08e)") == "1.0.0-beta.1")
    }

    @Test func transferCommandsAndStates() {
        let rec = SimRuntimeRecord(platform: .iOS, version: "27.0", build: "24A434", unpackedBytes: 16 << 30)
        let t = RuntimeTransfer(source: "/src/RuntimeRoot", record: rec, host: Self.host, totalBytes: 16 << 30)
        #expect(t.incoming == "/data/swiftcode/runtimes/iOS-27.0-24A434.incoming")
        #expect(t.rsyncArguments(ssh: "/usr/bin/ssh") == ["-a", "--partial", "-e", "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15",
                                                          "/src/RuntimeRoot/", "tester@sim-host:/data/swiftcode/runtimes/iOS-27.0-24A434.incoming/RuntimeRoot/"])
        #expect(t.finishCommand(markerJSON: "{}").hasSuffix("&& mv /data/swiftcode/runtimes/iOS-27.0-24A434.incoming /data/swiftcode/runtimes/iOS-27.0-24A434"))
        #expect(t.progressText(copiedKB: 4 << 20) == "4.0 GB of 16.0 GB (25%)")
        #expect(RuntimeTransferState.after(rsyncStatus: 0, copiedKB: 1) == .finished)
        #expect(RuntimeTransferState.after(rsyncStatus: 128 + 15, copiedKB: 5) == .interrupted(copiedKB: 5, reason: "The copy stopped (rsync status 143)."))
        #expect(RuntimeTransferState.after(rsyncStatus: 255, copiedKB: 5) == .interrupted(copiedKB: 5, reason: "The connection to the host was lost."))
        #expect(RuntimeTransferState.after(rsyncStatus: 2, copiedKB: 5) == .failed("rsync failed with status 2."))
    }

    static let setupOutput = """
    some noise from the login shell
    SWIFTCODE-SETUP mode=report version=1
    SWIFTCODE-FACT arch=aarch64
    SWIFTCODE-FACT kernel=6.8.12-tegra
    SWIFTCODE-USER data-folders mkdir -p /data/swiftcode/runtimes
    SWIFTCODE-ROOT kvm-group usermod -aG kvm tester
    SWIFTCODE-CHECK setup.os ok Linux (ubuntu 24.04).
    SWIFTCODE-CHECK setup.kvm missing /dev/kvm belongs to the kvm group; tester is not in it.
    SWIFTCODE-CHECK setup.data missing /data/swiftcode does not exist yet.
    SWIFTCODE-CHECK setup.firewall unknown ufw is on.
    SWIFTCODE-SVE arch=aarch64 sve=yes kvm=denied kernel=6.8.12-tegra error=no-kvm-access
    SWIFTCODE-DONE fail
    """

    @Test func setupOutputRootStepsFirst() {
        let o = HostSetupOutput.parse(Self.setupOutput)
        #expect(o.mode == "report" && o.passed == false && o.facts["kernel"] == "6.8.12-tegra")
        #expect(o.steps.map(\.id) == ["kvm-group", "data-folders"])
        #expect(o.rootSteps.map(\.command) == ["usermod -aG kvm tester"])
        #expect(!o.isSettled)
        let inv = HostSetupInvocation(dataDirectory: "/data/swiftcode")
        let list = o.checklist(destination: "tester@sim-host", invocation: inv)
        #expect(list.map(\.id) == ["setup.os", "setup.kvm", "setup.data", "setup.firewall", "setup.sve"])
        #expect(list[1].fix == .command("ssh -t tester@sim-host 'sudo bash ~/.cache/swiftcode/swiftcode-host-setup --root --data-dir /data/swiftcode --swift 6.4 --probe-seconds 3'"))
        #expect(list[2].fix == .action(.provisionApply))
        #expect(list[4].state == .unknown)
        #expect(inv.streamedCommand(mode: "report") == "bash -s -- --report --data-dir /data/swiftcode --swift 6.4 --probe-seconds 3")
        let settled = HostSetupOutput.parse("SWIFTCODE-CHECK setup.os ok Linux.\nSWIFTCODE-DONE pass\n")
        #expect(settled.isSettled && settled.passed == true)
    }

    @Test func portsVersionAndReleaseSteps() throws {
        #expect(RuntimeHostSettings.ports("47900/47901")! == (47900, 47901))
        #expect(RuntimeHostSettings.ports("47900 47901")! == (47900, 47901))
        #expect(RuntimeHostSettings.ports("47900") == nil && RuntimeHostSettings.ports("0/1") == nil)
        let inv = HostSetupInvocation(dataDirectory: "/data/swiftcode", swiftcodeVersion: "1.0.0-beta.2", tcpPort: 47900, udpPort: 47901)
        #expect(inv.arguments(mode: "apply") == ["--apply", "--data-dir", "/data/swiftcode", "--swift", "6.4", "--probe-seconds", "3",
                                                 "--swiftcode-version", "1.0.0-beta.2", "--tcp-port", "47900", "--udp-port", "47901"])
        let old = try JSONDecoder().decode(RuntimeHostSettings.self, from: Data(#"{"destination":"a@b","dataDirectory":"/d","linkName":"","swiftcodePath":""}"#.utf8))
        #expect(old.tcpPort == 47800 && old.udpPort == 47801 && old.destination == "a@b")
        let o = HostSetupOutput.parse("""
        SWIFTCODE-USER release t=/d/swiftcode/.download && curl …
        SWIFTCODE-USER swift t=$(mktemp -d) && …
        SWIFTCODE-CHECK setup.simhost missing No swiftcode-simhost here.
        SWIFTCODE-CHECK setup.swift missing No Swift; SwiftCode needs Swift 6.4.
        SWIFTCODE-CHECK setup.ports missing In use: 47800/tcp by bob (swiftcode-simhost). Choose free ports with --tcp-port N --udp-port M.
        SWIFTCODE-CHECK setup.selftest missing swiftcode-simhost check: SWIFTCODE_SIM_TREE /x has no .build/release/swiftcode-simd
        """)
        let list = o.checklist(destination: "a@b", invocation: inv)
        #expect(list.map(\.title) == ["swiftcode-simhost", "Swift toolchain", "Link ports", "Service self-test"])
        #expect(list[0].fix == .action(.provisionApply) && list[1].fix == .action(.provisionApply) && list[3].fix == .action(.provisionApply))
        #expect(list[2].fix == nil)
        #expect(RuntimeHostChecker.Command.version("", dataDirectory: "/d").contains("[ -x /d/bin/swiftcode ]"))
    }

    @Test func hostVersionFromTheReleaseFolder() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let top = dir.appendingPathComponent("swiftcode/SwiftCode-1.2.3-aarch64")
        try fm.createDirectory(at: top.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: top.appendingPathComponent("bin/swiftcode-simhost"))
        try Data("#!/bin/sh\necho 'version OPENSSL_3.2.0 not found' >&2; exit 1\n".utf8).write(to: top.appendingPathComponent("bin/swiftcode"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: top.appendingPathComponent("bin/swiftcode").path)
        try fm.createSymbolicLink(atPath: dir.appendingPathComponent("bin/swiftcode-simhost").path, withDestinationPath: top.appendingPathComponent("bin/swiftcode-simhost").path)
        try fm.createSymbolicLink(atPath: dir.appendingPathComponent("bin/swiftcode").path, withDestinationPath: top.appendingPathComponent("bin/swiftcode").path)
        func run() -> String {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", RuntimeHostChecker.Command.version("", dataDirectory: dir.path)]
            let out = Pipe()
            p.standardOutput = out
            try? p.run()
            p.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        #expect(RuntimeHostChecker.version(inVersionOutput: run()) == "1.2.3")
        try Data(#"{"name": "SwiftCode", "version": "1.2.4"}"#.utf8).write(to: top.appendingPathComponent("manifest.json"))
        #expect(RuntimeHostChecker.version(inVersionOutput: run()) == "1.2.4")
    }

    #if os(Linux)
    static let onLinux = true
    #else
    static let onLinux = false
    #endif

    @Test(.enabled(if: onLinux)) func secondApplyAfterAReleaseRunsNoReleaseStep() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        let v = "9.9.9", top = "SwiftCode-9.9.9-aarch64"
        let build = dir.appendingPathComponent("build/\(top)")
        for d in ["bin", "lib/swiftcode-sim/scripts", "lib/swiftcode-sim/.build/release", "lib/swiftcode-sim/SimShim/out"] {
            try fm.createDirectory(at: build.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        func script(_ rel: String, _ body: String) throws {
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: build.appendingPathComponent(rel))
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: build.appendingPathComponent(rel).path)
        }
        try script("bin/swiftcode-simhost", "echo \"swiftcode-simhost: unknown command $1\" >&2; exit 64")
        try script("bin/swiftcode", "echo 'libcurl.so.4: version OPENSSL_3.2.0 not found' >&2; exit 1")
        try script("lib/swiftcode-sim/scripts/swiftcode-sim.sh", "exit 0")
        try script("lib/swiftcode-sim/.build/release/swiftcode-simd", "exit 0")
        try Data().write(to: build.appendingPathComponent("lib/swiftcode-sim/SimShim/out/shim.bin"))
        let rel = dir.appendingPathComponent("rel")
        try fm.createDirectory(at: rel, withIntermediateDirectories: true)
        #expect(shell("cd \(dir.appendingPathComponent("build").path.shellQuoted) && tar -cJf \(rel.path.shellQuoted)/\(top).tar.xz \(top) && cd \(rel.path.shellQuoted) && sha256sum \(top).tar.xz > SHA256SUMS.txt") == 0)
        let data = dir.appendingPathComponent("data"), rt = data.appendingPathComponent("runtimes/iOS-27.0-24A434/RuntimeRoot")
        try fm.createDirectory(at: rt.appendingPathComponent("sbin"), withIntermediateDirectories: true)
        try Data().write(to: rt.appendingPathComponent("sbin/launchd_sim"))
        let file = dir.appendingPathComponent("swiftcode-host-setup")
        try HostSetupScript.text.write(to: file, atomically: true, encoding: .utf8)
        let fakeSwiftly = dir.appendingPathComponent("swiftly")
        try fm.createDirectory(at: fakeSwiftly.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho 'Swift version 6.4.2 (stand-in)'\n".utf8).write(to: fakeSwiftly.appendingPathComponent("bin/swift"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeSwiftly.appendingPathComponent("bin/swift").path)
        try Data("export PATH=\"\(fakeSwiftly.path)/bin:/usr/bin:/bin\"\n".utf8).write(to: fakeSwiftly.appendingPathComponent("env.sh"))
        func setup(_ mode: String) -> HostSetupOutput {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/bash")
            p.arguments = [file.path, "--" + mode, "--data-dir", data.path, "--config-dir", dir.appendingPathComponent("config").path,
                           "--swiftcode-version", v, "--release-base", "file://" + rel.path, "--no-probe", "--min-free-gb", "0", "--tcp-port", "47890", "--udp-port", "47891"]
            p.environment = ["PATH": fakeSwiftly.path + "/bin:/usr/bin:/bin", "HOME": dir.path, "SWIFTLY_HOME_DIR": fakeSwiftly.path,
                             "SWIFTCODE_SETUP_ARCH": "aarch64"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            try? p.run()
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            return HostSetupOutput.parse(text)
        }
        let first = setup("report")
        #expect(first.userSteps.contains { $0.id == "release" })
        try #require(!first.steps.contains { $0.id == "swift" }, "the stand-in Swift was not used; not applying")
        let applied = setup("apply")
        #expect(applied.ran["release"] == true)
        #expect(applied.facts["swiftcode_installed"] == v)
        #expect(!applied.userSteps.contains { $0.id == "release" })
        let selftest = try #require(applied.checks.first { $0.id == "setup.selftest" })
        #expect(selftest.state == .unknown && selftest.reason.contains("predates swiftcode-simhost check"), "\(selftest)")
        #expect(applied.checks.first { $0.id == "setup.service" }?.state == .ok)
        let again = setup("apply")
        #expect(again.ran.isEmpty, "\(again.ran)")
        #expect(!again.userSteps.contains { $0.id == "release" })
        #expect(again.checks.first { $0.id == "setup.simhost" }?.state == .ok)
    }

    @Test func sveDecision() {
        typealias F = KVMSVEProbe.Facts
        #expect(KVMSVEProbe.verdict(F(architecture: "x86_64", hasSVE: false, kvm: "access")) ==
                .notApplicable("This host is x86_64; the bug is in KVM on arm64 with SVE."))
        if case .notApplicable = KVMSVEProbe.verdict(F(architecture: "aarch64", hasSVE: false, kvm: "access")) {} else { Issue.record("no SVE") }
        #expect(KVMSVEProbe.verdict(F(architecture: "aarch64", hasSVE: true, kvm: "access", runs: 21_300_000, lost: 149_873)) == .affected(lost: 149_873, runs: 21_300_000))
        #expect(KVMSVEProbe.verdict(F(architecture: "aarch64", hasSVE: true, kvm: "access", runs: 21_700_000, lost: 0)) == .fixed(runs: 21_700_000))
        #expect(KVMSVEProbe.verdict(F(architecture: "arm64", hasSVE: true, kvm: "access", runs: 50, lost: 1)) == .affected(lost: 1, runs: 50))
        if case .unknown = KVMSVEProbe.verdict(F(architecture: "aarch64", hasSVE: true, kvm: "access", runs: 50, lost: 0)) {} else { Issue.record("few runs") }
        if case .unknown = KVMSVEProbe.verdict(F(architecture: "aarch64", hasSVE: true, kvm: "access", error: "compile-failed")) {} else { Issue.record("error") }
        let affected = KVMSVEProbe.check(F(["arch": "aarch64", "sve": "yes", "kvm": "access", "kernel": "6.8.12-tegra", "runs": "2000000", "lost": "4038"]))
        #expect(affected.state == .missing && affected.reason.contains("mitigations are on") && affected.reason.contains("6.8.12-tegra"))
        #expect(affected.fix == .instructions("How to get a kernel with the fix: \(KVMSVEProbe.postmortem)"))
        #expect(KVMSVEProbe.check(F(["arch": "x86_64", "sve": "no", "kvm": "access", "error": "not-arm64"])).state == .notApplicable)
    }

    @Test func scriptIsValidBashAndOnlyReportsOffLinux() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(HostSetupScript.fileName)
        try HostSetupScript.text.write(to: url, atomically: true, encoding: .utf8)
        #expect(shell("bash -n \(url.path.shellQuoted)") == 0)
        #expect(HostSetupScript.text.contains("int main(int argc"))
        #expect(!HostSetupScript.text.contains("@PROBE_SOURCE@"))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [url.path, "--report", "--data-dir", dir.appendingPathComponent("data").path, "--config-dir", dir.appendingPathComponent("conf").path]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        let o = HostSetupOutput.parse(text)
        #if os(macOS)
        #expect(o.checks.first?.id == "setup.os" && o.checks.first?.state == .missing)
        #expect(o.passed == false && o.sve?["error"]?.string == "not-linux")
        #endif
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("data").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("conf").path))
    }

    @MainActor @Test func sessionConfirmsBeforeAnything() async throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let d = UserDefaults(suiteName: "swiftcode-runtime-tests-\(UUID().uuidString)")!
        let s = RuntimeSetupSession(machine: Self.mac, defaults: d, folder: dir.appendingPathComponent("rt").path, localRunner: R(answers: Self.macReady))
        #expect(s.steps == [.target, .runtimes, .download, .add, .finish])
        await s.recheck().value
        #expect(s.report?.check("runtime.iOS")?.state == .ok)
        s.next()
        #expect(s.step == .runtimes && s.state(of: .runtimes) == .ok)
        let dmg = dir.appendingPathComponent("iOS 27.0 Simulator Runtime.dmg")
        try Data().write(to: dmg)
        s.pick(path: dmg.path)
        #expect(s.pickedAction == .importImage(path: dmg.path, tool: .simctl))
        s.request(s.pickedAction!)
        #expect(s.confirmation?.command == "xcrun simctl runtime add '\(dmg.path)'")
        s.cancelConfirmation()
        #expect(s.confirmation == nil && s.running == nil)
        let b = try Self.fakeBundle(in: dir)
        s.pick(path: b.path)
        #expect(s.picked?.record?.title == "iOS 27.0 (24A434)" && s.pickedAction == nil)
        s.setUseHost(true)
        #expect(s.steps == [.target, .host, .prepare, .runtimes, .download, .add, .finish])
        #expect(RuntimeSetupChoices.load(d).useHost)
        s.setHost(Self.host)
        s.pick(path: b.path)
        guard case .copyToHost(let src, let rec, "tester@sim-host")? = s.pickedAction else { Issue.record("expected a copy to the host"); return }
        #expect(src.hasSuffix("Contents/Resources/RuntimeRoot") && rec.folderName == "iOS-27.0-24A434")
        s.request(.copyToHost(source: src, record: rec, host: "tester@sim-host"))
        #expect(s.confirmation?.command.contains("rsync -a --partial") == true)
        s.cancelConfirmation()
        let hostCopy = SimRuntimeRecord(platform: .iOS, version: "27.0", build: "24A434", location: .host("tester@sim-host"),
                                        owner: .swiftcode(folder: "/data/swiftcode/runtimes/iOS-27.0-24A434"))
        s.request(.remove(hostCopy))
        #expect(s.confirmation?.isDestructive == true)
        #expect(s.confirmation?.command == "ssh tester@sim-host 'test -f /data/swiftcode/runtimes/iOS-27.0-24A434/swiftcode-runtime.json && rm -rf /data/swiftcode/runtimes/iOS-27.0-24A434'")
        s.cancelConfirmation()
        let x = RuntimeSetupSession(machine: Self.x86, defaults: UserDefaults(suiteName: "swiftcode-runtime-tests-\(UUID().uuidString)")!, folder: dir.path)
        #expect(x.choices.useHost)
        x.setUseHost(false)
        #expect(x.choices.useHost)
    }

    @Test func commandLineShowsTheSameChecklist() async {
        final class Lines: @unchecked Sendable {
            private let lock = NSLock()
            private var all: [String] = []
            func add(_ s: String) { lock.withLock { all.append(s) } }
            var text: String { lock.withLock { all.joined(separator: "\n") } }
        }
        let lines = Lines()
        let status = await RuntimeCLI.main(["check", "--platform", "iOS", "--platform", "visionOS", "--host", "tester@sim-host", "--data", "/data/swiftcode"],
                                           runner: R(answers: Self.macReady), hostRunner: R(answers: Self.hostReady), machine: Self.mac) { lines.add($0) }
        #expect(status == 1)
        #expect(lines.text.contains("iOS 27.0 (24A434)  7.3 GB  ready  Xcode's (read-only)"))
        #expect(lines.text.contains("ok       Reachable: tester@sim-host answers with your ssh key."))
        #expect(lines.text.contains("MISSING  Runtime for visionOS"))
        let script = Lines()
        #expect(await RuntimeCLI.main(["script"]) { script.add($0) } == 0)
        #expect(script.text.hasPrefix("#!/usr/bin/env bash"))
        #expect(await RuntimeCLI.main(["nonsense"]) { _ in } == 64)
    }

    @MainActor @Test func copiedRuntimeBecomesARuntimeRootOfThatHost() {
        let d = UserDefaults(suiteName: "swiftcode-runtime-tests-\(UUID().uuidString)")!
        var settings = RemoteSimulatorSettings(destination: "tester@sim-host", dataDirectory: "/data/swiftcode", runtimeRoot: "/rt/iOS-27.1/RuntimeRoot", simdPath: "/x")
        settings.save(d)
        let s = RuntimeSetupSession(machine: Self.mac, defaults: d, folder: "/nonexistent")
        let rec = SimRuntimeRecord(platform: .iOS, version: "27.0", build: "24A434")
        let root = "/data/swiftcode/runtimes/iOS-27.0-24A434/RuntimeRoot"
        #expect(!s.registerRemoteRoot(root, record: rec, host: "other@host"))
        #expect(s.registerRemoteRoot(root, record: rec, host: "tester@sim-host"))
        settings = RemoteSimulatorSettings.load(d)
        #expect(settings.otherRuntimeRoots == [root] && settings.runtimeVersion(forRoot: root) == "27.0")
        #expect(settings.targets.contains { $0.runtimeRoot == root })
        s.unregisterRemoteRoot(root, host: "tester@sim-host")
        #expect(RemoteSimulatorSettings.load(d).otherRuntimeRoots.isEmpty)
    }

    @Test func linkHostsFromTrustedPeers() throws {
        let dir = Self.temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"[{"name":"sim-host","publicKey":"AA==","role":"host","added":"x"},{"name":"laptop","publicKey":"AA==","role":"client","added":"x"}]"#.utf8)
            .write(to: dir.appendingPathComponent("trusted-peers.json"))
        #expect(RuntimeSetupSession.linkHosts(environment: ["SWIFTCODE_SIM_LINK_HOME": dir.path]) == ["sim-host"])
    }
}
