import Foundation
import YcodeDebug
import YcodeBuild
import YcodeProfiler
import YcodeSubprocess

public struct RemoteProfile: Sendable, Equatable {
    public var remotePath: String
    public var rate: Int
    public var localURL: URL
    public init(remotePath: String, rate: Int = 1000, localURL: URL) {
        self.remotePath = remotePath
        self.rate = rate
        self.localURL = localURL
    }

    public static var localDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/SwiftCode/Gauge", isDirectory: true)
    }

    public static func fileName(app: String, date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(app)-\(f.string(from: date)).gaugetrace"
    }
}

public struct RemoteSimulatorSettings: Equatable, Sendable {
    public var destination: String
    public var dataDirectory: String
    public var runtimeRoot: String
    public var simdPath: String
    public var deviceName: String
    public var otherRuntimeRoots: [String] = []
    public var runtimeVersions: [String: String] = [:]
    public var runtimePlatforms: [String: String] = [:]
    public var createdDevices: [RemoteCreatedDevice] = []
    public var additionalArguments: String = ""
    public var leanBoot = false
    public var keepServices: String = ""
    public static let leanBootHelp = "Development option: skips background services such as Siri, Spotlight, suggestions and photo analysis, so apps that use them see them missing. Off (the default), every service boots."
    public static let leanBootKey = "SwiftCode.remote.leanBootChoice"
    public static let leanBootLegacyKey = "SwiftCode.remote.leanBoot"
    public var warmBoot = true
    public static let warmBootHelp = "Keeps the device's state between runs: when a run stops, the device is saved, and the next run continues from it in seconds instead of booting; apps and their data stay until the device is erased. Saves are replaced when the simulator or the runtime changes. Turn off to boot from scratch every time."
    public var camera = "off"
    public var cameraChosen = false
    public var visionDisplay = ""
    public static let headsetVisionDisplay = "2160x3840"
    public static let cameraModes = ["off", "on", "synthetic"]
    public static let cameraHelp = "Gives apps a camera: the host's USB webcam (or a test pattern when it has none) appears as the device's back camera (an iPad's external camera). Off by default."
    public var ssh: String
    public var rsync: String

    public init(destination: String = "", dataDirectory: String = "", runtimeRoot: String = "", simdPath: String = "",
                deviceName: String = "swiftcode-device", ssh: String = HostTool.path("ssh"), rsync: String = HostTool.path("rsync")) {
        self.destination = destination
        self.dataDirectory = dataDirectory
        self.runtimeRoot = runtimeRoot
        self.simdPath = simdPath
        self.deviceName = deviceName
        self.ssh = ssh
        self.rsync = rsync
    }

    public var isConfigured: Bool { !destination.isEmpty && !dataDirectory.isEmpty && !runtimeRoot.isEmpty && !simdPath.isEmpty }

    public var runtimeVersion: String?

    public static func version(inPath p: String) -> String? {
        guard let r = p.range(of: #"iOS[ _-]?([0-9]+(\.[0-9]+)+)"#, options: .regularExpression) else { return nil }
        let m = p[r].drop { !$0.isNumber }
        return String(m)
    }

    public static func saveRuntimeVersion(_ version: String, root: String, _ d: UserDefaults, primary: Bool = true) {
        if primary {
            d.set(version, forKey: "SwiftCode.remote.runtimeVersion")
            d.set(root, forKey: "SwiftCode.remote.runtimeVersionRoot")
        }
        var all = d.dictionary(forKey: "SwiftCode.remote.runtimeVersions") as? [String: String] ?? [:]
        all[root] = version
        d.set(all, forKey: "SwiftCode.remote.runtimeVersions")
    }

    public static func saveRuntimePlatform(_ platform: String, root: String, _ d: UserDefaults) {
        var all = d.dictionary(forKey: "SwiftCode.remote.runtimePlatforms") as? [String: String] ?? [:]
        all[root] = platform
        d.set(all, forKey: "SwiftCode.remote.runtimePlatforms")
    }

    public static func hasRuntimeVersion(for root: String, _ d: UserDefaults) -> Bool {
        if d.string(forKey: "SwiftCode.remote.runtimeVersionRoot") == root && d.string(forKey: "SwiftCode.remote.runtimeVersion") != nil { return true }
        return (d.dictionary(forKey: "SwiftCode.remote.runtimeVersions") as? [String: String])?[root] != nil
    }

    static let keys = ["destination", "dataDirectory", "runtimeRoot", "simdPath", "deviceName"]

    public static func load(_ d: UserDefaults) -> RemoteSimulatorSettings {
        var s = RemoteSimulatorSettings()
        s.destination = d.string(forKey: "SwiftCode.remote.destination") ?? ""
        s.dataDirectory = d.string(forKey: "SwiftCode.remote.dataDirectory") ?? ""
        s.runtimeRoot = d.string(forKey: "SwiftCode.remote.runtimeRoot") ?? ""
        s.simdPath = d.string(forKey: "SwiftCode.remote.simdPath") ?? ""
        s.deviceName = d.string(forKey: "SwiftCode.remote.deviceName") ?? "swiftcode-device"
        s.otherRuntimeRoots = d.stringArray(forKey: "SwiftCode.remote.otherRuntimeRoots") ?? []
        s.runtimeVersions = d.dictionary(forKey: "SwiftCode.remote.runtimeVersions") as? [String: String] ?? [:]
        s.runtimePlatforms = d.dictionary(forKey: "SwiftCode.remote.runtimePlatforms") as? [String: String] ?? [:]
        s.createdDevices = createdDevices(d)
        s.additionalArguments = d.string(forKey: "SwiftCode.remote.additionalArguments") ?? ""
        s.leanBoot = d.object(forKey: leanBootKey) as? Bool ?? false
        s.keepServices = d.string(forKey: "SwiftCode.remote.keepServices") ?? ""
        s.warmBoot = d.object(forKey: "SwiftCode.remote.warmBoot") as? Bool ?? true
        s.camera = d.string(forKey: "SwiftCode.remote.camera").flatMap { cameraModes.contains($0) ? $0 : nil } ?? "off"
        s.cameraChosen = d.object(forKey: "SwiftCode.remote.camera") != nil
        s.visionDisplay = d.string(forKey: "SwiftCode.remote.visionDisplay") ?? ""
        s.runtimeVersion = hasRuntimeVersion(for: s.runtimeRoot, d) ? d.string(forKey: "SwiftCode.remote.runtimeVersion") : version(inPath: s.runtimeRoot)
        return s
    }

    public func save(_ d: UserDefaults) {
        d.set(destination, forKey: "SwiftCode.remote.destination")
        d.set(dataDirectory, forKey: "SwiftCode.remote.dataDirectory")
        d.set(runtimeRoot, forKey: "SwiftCode.remote.runtimeRoot")
        d.set(simdPath, forKey: "SwiftCode.remote.simdPath")
        d.set(deviceName, forKey: "SwiftCode.remote.deviceName")
        d.set(otherRuntimeRoots, forKey: "SwiftCode.remote.otherRuntimeRoots")
        d.set(additionalArguments, forKey: "SwiftCode.remote.additionalArguments")
        d.set(leanBoot, forKey: Self.leanBootKey)
        d.removeObject(forKey: Self.leanBootLegacyKey)
        d.set(keepServices, forKey: "SwiftCode.remote.keepServices")
        d.set(warmBoot, forKey: "SwiftCode.remote.warmBoot")
        if cameraChosen { d.set(camera, forKey: "SwiftCode.remote.camera") }
        d.set(visionDisplay, forKey: "SwiftCode.remote.visionDisplay")
    }
}

public struct RemoteSimulator: Sendable {
    public var settings: RemoteSimulatorSettings
    public var target: RemoteSimulatorTarget?
    public var displaySocketName: String?
    public init(settings: RemoteSimulatorSettings, destination: Destination? = nil) {
        self.settings = settings
        self.target = settings.target(for: destination)
    }

    public init(settings: RemoteSimulatorSettings, target: RemoteSimulatorTarget?) {
        self.settings = settings
        self.target = target
    }

    public static func all(_ settings: RemoteSimulatorSettings) -> [RemoteSimulator] {
        settings.targets.map { RemoteSimulator(settings: settings, target: $0) }
    }

    public static func hub(_ settings: RemoteSimulatorSettings) -> [RemoteSimulator] {
        settings.hubTargets.map { RemoteSimulator(settings: settings, target: $0) }
    }

    public var runtimeRoot: String { target?.runtimeRoot ?? settings.runtimeRoot }
    public var runtimeVersion: String? { target.map(\.runtimeVersion) ?? settings.runtimeVersion }

    public static let identifier = "swiftcode-remote-simulator"
    public static let deviceName = "SwiftCode Simulator"
    public static let destination = Destination(name: deviceName, specifier: "generic/platform=iOS Simulator",
                                                platform: "iOS", kind: .generic, identifier: identifier)

    public static func destination(runtimeVersion: String?) -> Destination {
        var d = destination
        d.osVersion = runtimeVersion
        return d
    }

    public var destination: Destination { target?.destination ?? Self.destination(runtimeVersion: settings.runtimeVersion) }

    public static func destinations(_ settings: RemoteSimulatorSettings, pairs: [RemoteDevicePair] = []) -> [Destination] {
        settings.targets.map(\.destination) + settings.watchTargets.map(\.destination) + settings.pairedDestinations(pairs)
    }

    public var stopGrace: TimeInterval = 150

    public static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    public func remoteAppPath(_ app: URL) -> String { "\(settings.dataDirectory)/apps/\(app.lastPathComponent)" }
    public var remoteDevicePath: String { "\(settings.dataDirectory)/devices/\(target?.deviceDirectoryName ?? settings.deviceName)" }

    var sshOptions: [String] { ["-o", "BatchMode=yes"] }

    public func sshArguments(_ command: String) -> [String] { sshOptions + [settings.destination, command] }

    public func mkdirCommand(_ app: URL) -> String {
        "mkdir -p \(Self.quote("\(settings.dataDirectory)/apps")) \(Self.quote("\(settings.dataDirectory)/display")) \(Self.quote(profilesDirectory))"
    }

    public var profilesDirectory: String { "\(settings.dataDirectory)/profiles" }

    public func profile(app: URL, rate: Int = 1000, date: Date = Date()) -> RemoteProfile {
        let name = RemoteProfile.fileName(app: app.deletingPathExtension().lastPathComponent, date: date)
        return RemoteProfile(remotePath: "\(profilesDirectory)/\(name)", rate: rate,
                             localURL: RemoteProfile.localDirectory.appendingPathComponent(name))
    }

    public func fetchArguments(_ profile: RemoteProfile) -> [String] {
        ["-az", "-e", ([settings.ssh] + sshOptions).joined(separator: " "),
         "\(settings.destination):\(profile.remotePath)", profile.localURL.path]
    }

    public func fetchProfile(_ profile: RemoteProfile) throws {
        try FileManager.default.createDirectory(at: profile.localURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let (r, ro) = runLocal(settings.rsync, fetchArguments(profile))
        guard r == 0 else { throw Simctl.Failure(description: "the trace could not be copied from \(settings.destination) (rsync \(r)): \(ro)") }
    }

    public func rsyncArguments(_ app: URL) -> [String] {
        ["-az", "--delete", "-e", ([settings.ssh] + sshOptions).joined(separator: " "),
         app.path + "/", "\(settings.destination):\(remoteAppPath(app))/"]
    }

    public func runCommand(app: URL, bundleID: String, profile: RemoteProfile? = nil, debug: Bool = false) -> String {
        let q = Self.quote
        return "echo SWIFTCODE-REMOTE-PID $$; exec \(environmentPrefix)\(q(settings.simdPath)) --device \(q(remoteDevicePath)) --runtime-root \(q(runtimeRoot))"
            + (target?.deviceTypeArguments ?? []).map { " " + q($0) }.joined()
            + " --install-app \(q(remoteAppPath(app))) --launch \(q(bundleID)) --environment-overrides"
            + (profile.map { " --profile \(q($0.remotePath)) --profile-rate \(q(String($0.rate)))" } ?? "")
            + (debug ? debugServerArguments.map { " " + q($0) }.joined() : "")
            + displayServerArguments.map { " " + q($0) }.joined()
            + Self.words(settings.additionalArguments).map { " " + q($0) }.joined()
            + cameraArguments.map { " " + q($0) }.joined()
            + visionDisplayArguments.map { " " + q($0) }.joined()
    }

    public static let testDestination = "platform=iOS Simulator,name=SwiftCode Simulator,arch=arm64"

    public var testEnvironment: [String: String] {
        let q = Self.quote
        let options = (target?.deviceTypeArguments ?? []) + Self.words(settings.additionalArguments) + cameraArguments
        var env = [
            "SWIFTCODE_SIM_HOST": settings.destination, "SWIFTCODE_SIM_DATA": settings.dataDirectory, "SWIFTCODE_SIM_RUNTIME": runtimeRoot,
            "SWIFTCODE_SIM_SIMD": settings.simdPath, "SWIFTCODE_SIM_DEVICE": target?.deviceDirectoryName ?? settings.deviceName,
            "SWIFTCODE_SIM_OPTIONS": options.map(q).joined(separator: " "),
            "SWIFTCODE_SIM_ENV": ("SWIFTCODE_WARM_BOOT=\(settings.warmBoot ? 1 : 0) " + leanBootVariables).trimmingCharacters(in: .whitespaces),
        ]
        if settings.ssh != HostTool.path("ssh") { env["SWIFTCODE_SSH"] = settings.ssh }
        if settings.rsync != HostTool.path("rsync") { env["SWIFTCODE_RSYNC"] = settings.rsync }
        return env
    }

    public var visionDisplayArguments: [String] {
        target?.isVision == true && !settings.visionDisplay.isEmpty ? ["--vision-display", settings.visionDisplay] : []
    }

    public var cameraArguments: [String] {
        settings.cameraChosen || settings.camera != "off" ? ["--camera", settings.camera] : []
    }

    public var environmentPrefix: String {
        "env SWIFTCODE_WARM_BOOT=\(settings.warmBoot ? 1 : 0) " + leanBootVariables
    }

    public var leanBootVariables: String {
        guard settings.leanBoot else { return "" }
        let labels = settings.keepServices.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return "SWIFTCODE_LEAN_BOOT=daemons " + (labels.isEmpty ? "" : "SWIFTCODE_LEAN_BOOT_KEEP=\(Self.quote(labels.joined(separator: ","))) ")
    }

    public static func words(_ text: String) -> [String] {
        var out: [String] = [], cur = "", inWord = false
        var quote: Character?
        var escape = false
        for c in text {
            if escape { cur.append(c); escape = false; inWord = true; continue }
            if let q = quote {
                if c == q { quote = nil } else if c == "\\" && q == "\"" { escape = true } else { cur.append(c) }
                continue
            }
            if c == "'" || c == "\"" { quote = c; inWord = true }
            else if c == "\\" { escape = true }
            else if c.isWhitespace { if inWord { out.append(cur); cur = ""; inWord = false } }
            else { cur.append(c); inWord = true }
        }
        if inWord { out.append(cur) }
        return out
    }

    public enum Phase: Equatable, Sendable { case booting, launching(retries: Int), running }
    public static func phase(after line: String, current: Phase) -> Phase {
        let l = line.lowercased()
        if l.hasPrefix("launched ") || l.contains(" launched ") && l.contains(" pid ") { return .running }
        if current == .running { return .running }
        if l.contains("no completion within") {
            if case .launching(let n) = current { return .launching(retries: n + 1) }
            return .launching(retries: 1)
        }
        if l.contains("install") || l.contains("launch") || l.contains("open") {
            if case .launching = current { return current }
            return .launching(retries: 0)
        }
        return current
    }

    public static func status(_ p: Phase, app: String, device: String = RemoteSimulator.deviceName) -> String {
        switch p {
        case .booting, .launching: WorkspaceSession.RunActivityText.launching(app)
        case .running: WorkspaceSession.RunActivityText.running(app, on: device)
        }
    }

    public var debugSocketPath: String {
        "\(settings.dataDirectory)/debug/\(target?.deviceDirectoryName ?? settings.deviceName).sock"
    }

    public var debugServerArguments: [String] { ["--debug-server", "unix:" + debugSocketPath] }

    public static let debugStubListeningMarker = "debug: gdb-remote stub listening on "

    public func debugForwardArguments(localPort: Int) -> [String] {
        sshOptions + ["-N", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=15",
                      "-L", "127.0.0.1:\(localPort):\(debugSocketPath)", settings.destination]
    }

    public static func attachesDebugger(_ d: UserDefaults) -> Bool { d.object(forKey: "SwiftCode.remote.debugger") as? Bool ?? true }

    public static func debuggerSettings(appDirectory: String) -> [String] {
        ["settings set target.exec-search-paths \"\(appDirectory)\"",
         "settings set target.process.memory-cache-line-size 16384",
         "settings set target.enable-trampoline-support false"]
    }

    static var streamSocketType: Int32 {
        #if canImport(Glibc)
        Int32(SOCK_STREAM.rawValue)
        #else
        SOCK_STREAM
        #endif
    }

    public static func freeLoopbackPort() -> Int? {
        let fd = socket(AF_INET, RemoteSimulator.streamSocketType, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard bound == 0 else { return nil }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        guard named == 0 else { return nil }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    public static func remotePID(_ line: String) -> Int? {
        guard line.hasPrefix("SWIFTCODE-REMOTE-PID ") else { return nil }
        return Int(line.dropFirst("SWIFTCODE-REMOTE-PID ".count).trimmingCharacters(in: .whitespaces))
    }

    @discardableResult
    package func runLocal(_ exe: String, _ args: [String], timeout: TimeInterval? = nil) -> (Int32, String) {
        let (status, data) = runLocalData(exe, args, errors: true, timeout: timeout)
        return (status, String(decoding: data, as: UTF8.self))
    }

    func runLocalData(_ exe: String, _ args: [String], errors: Bool, timeout: TimeInterval? = nil) -> (Int32, Data) {
        MainThreadGuard.blockingCall("\(URL(fileURLWithPath: exe).lastPathComponent) \(args.prefix(2).joined(separator: " "))")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = errors ? out : FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return (127, Data("could not run \(exe)".utf8)) }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, d)
    }

    public func upload(_ app: URL) throws {
        let (m, mo) = runLocal(settings.ssh, sshArguments(mkdirCommand(app)))
        guard m == 0 else { throw Simctl.Failure(description: "ssh mkdir failed (\(m)): \(mo)") }
        let (r, ro) = runLocal(settings.rsync, rsyncArguments(app))
        guard r == 0 else { throw Simctl.Failure(description: "rsync failed (\(r)): \(ro)") }
    }

    @discardableResult
    public func signalRemote(_ pid: Int, signal: String) -> Int32 {
        runLocal(settings.ssh, sshArguments("kill -\(signal) \(pid)")).0
    }

    public var isFoldable: Bool { target?.deviceType.isFoldable ?? false }

    public func controlCommand(_ words: [String]) -> String {
        "exec \(Self.quote(settings.simdPath)) --device \(Self.quote(remoteDevicePath)) --control"
            + words.map { " " + Self.quote($0) }.joined()
    }

    public func control(_ words: [String]) -> (Int32, String) {
        runLocal(settings.ssh, sshArguments(controlCommand(words)), timeout: controlTimeout)
    }

    public var controlTimeout: TimeInterval = 60

    public static func hingeAngle(stateReply: String) -> Int? {
        guard let r = stateReply.range(of: #"angle (\d+)"#, options: .regularExpression) else { return nil }
        return Int(stateReply[r].dropFirst("angle ".count))
    }

    public var eraseCommand: String {
        "exec \(Self.quote(settings.simdPath)) --erase --device \(Self.quote(remoteDevicePath))"
    }

    public func erase() -> (Int32, String) {
        runLocal(settings.ssh, sshArguments(eraseCommand))
    }

    public var runtimeVersionCommand: String {
        "cat \(Self.quote(runtimeRoot + "/System/Library/CoreServices/SystemVersion.plist"))"
    }

    public static func productVersion(plist data: Data) -> String? {
        let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return p?["ProductVersion"] as? String
    }

    public static func productPlatform(plist data: Data) -> String? {
        guard let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        switch p["ProductName"] as? String {
        case "Watch OS": return "watchOS"
        case "xrOS": return "visionOS"
        default: return "iOS"
        }
    }

    public func readRuntimeVersion() -> String? { readRuntimeSystemVersion()?.version }

    public func readRuntimeSystemVersion() -> (version: String, platform: String)? {
        let (status, data) = runLocalData(settings.ssh, sshArguments(runtimeVersionCommand), errors: false)
        guard status == 0, let v = Self.productVersion(plist: data) else { return nil }
        return (v, Self.productPlatform(plist: data) ?? "iOS")
    }

    public static func stoppingStatus(app: String, saves: Bool) -> String {
        saves ? "Stopping \(app) — saving SwiftCode Simulator…" : "Stopping \(app)…"
    }

    public static func endsStop(_ line: String) -> Bool {
        line.hasPrefix("swiftcode-sim: ") && (line.contains("the device was saved") || line.contains("the device was not saved"))
    }
}

extension Destination {
    public var isSwiftCodeRemoteSimulator: Bool {
        guard let identifier else { return false }
        return identifier == RemoteSimulator.identifier || identifier.hasPrefix(RemoteSimulator.identifier + ":")
    }
}

extension WorkspaceSession {
    public func runOnRemoteSimulator(app appURL: URL, remote: RemoteSimulator, profile: RemoteProfile? = nil,
                                     onTrace: (@MainActor (Result<URL, Error>) -> Void)? = nil) async {
        func fail(_ text: String) { onTrace?(.failure(RemoteRunFailure(description: text))) }
        guard let app = AppBundle(url: appURL) else {
            appendConsole("SwiftCode: \(appURL.lastPathComponent) is not an application bundle.\n")
            fail("\(appURL.lastPathComponent) is not an application bundle")
            return
        }
        guard remote.settings.isConfigured else {
            appendConsole("SwiftCode: set the remote simulator in Settings ▸ Simulators first.\n")
            fail("the remote simulator is not set up (Settings ▸ Simulators)")
            return
        }
        let state = SimulatorRunState(target: .remote(destination: remote.settings.destination), app: app)
        state.remote = remote
        simulatorRun = state
        let device = remote.destination.name
        setActivity(.running(RemoteSimulator.status(.booting, app: app.executable, device: device)))
        do {
            try await Task.detached { try remote.upload(appURL) }.value
        } catch {
            appendConsole("SwiftCode: \(error)\n")
            simulatorRun = nil
            setActivity(.finished("Run failed"))
            fail("the upload failed: \(error)")
            return
        }
        if state.stopRequested {
            appendConsole("SwiftCode: stopped before \(app.executable) was launched.\n", kind: .debugger)
            if simulatorRun === state { simulatorRun = nil }
            setActivity(.idle)
            fail("stopped before \(app.executable) was launched")
            return
        }
        if RemoteDeviceSessions.shared.isRunning(remote) {
            appendConsole("SwiftCode: shutting down \(device) (started in Device Hub) for the run\n", kind: .debugger)
            await RemoteDeviceSessions.shared.shutDown(remote)
        }
        appendConsole("SwiftCode: launching \(app.bundleID) on \(remote.settings.destination)\n")
        var phase = RemoteSimulator.Phase.booting
        var stubListening = false
        setActivity(.running(RemoteSimulator.status(phase, app: app.executable, device: device)))
        let debug = profile == nil && RemoteSimulator.attachesDebugger(Preferences.shared.defaults)
        let proc = StreamingProcess(executable: remote.settings.ssh,
                                    arguments: remote.sshArguments(remote.runCommand(app: appURL, bundleID: app.bundleID, profile: profile, debug: debug)))
        state.process = proc
        do {
            try proc.start(onLine: { [weak self, weak state] line in
                guard let self, let state else { return }
                if let pid = RemoteSimulator.remotePID(line) {
                    state.remotePID = pid
                    if state.stopRequested { self.sendRemoteStop(state, pid: pid, remote: remote) }
                    return
                }
                if debug, !stubListening, line.contains(RemoteSimulator.debugStubListeningMarker) { stubListening = true }
                if !state.stopRequested {
                    let next = RemoteSimulator.phase(after: line, current: phase)
                    if next != phase {
                        phase = next
                        let text = RemoteSimulator.status(phase, app: app.executable, device: device)
                        if self.activity != .running(text) { self.setActivity(.running(text)) }
                        if debug, stubListening, phase == .running {
                            self.setActivity(.running(WorkspaceSession.RunActivityText.configuringDebugger))
                            Task { [weak self] in await self?.attachToRemoteSimulatorApp(state, remote: remote, app: appURL, device: device) }
                        }
                    }
                }
                let status = state.stopRequested || line.hasPrefix("swiftcode-sim: ") || phase != .running || line.lowercased().hasPrefix("launched ")
                self.appendConsole(line + "\n", kind: status ? .debugger : .target)
                if state.stopRequested, RemoteSimulator.endsStop(line) {
                    Task { [weak state] in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard let state, state.exitStatus == nil else { return }
                        state.closedByIDE = true
                        state.process?.signal(SIGINT)
                    }
                }
            }, onExit: { [weak self, weak state] status in
                state?.exitStatus = status
                if let f = state?.debugForward, f.isRunning { f.terminate() }
                guard let self else { return }
                let stopped = state?.stopRequested == true
                if state?.closedByIDE == true {
                    self.appendConsole("SwiftCode Simulator stopped\n")
                } else {
                    self.appendConsole("SwiftCode Simulator ended with status \(status)\(status == 0 || stopped ? "" : " (see swiftcode-simd's exit codes)")\n")
                }
                if self.simulatorRun === state { self.simulatorRun = nil }
                self.setActivity(.finished(status == 0 || stopped ? WorkspaceSession.RunActivityText.finished(app.executable, on: device) : "Run failed"))
                if let profile {
                    self.appendConsole("SwiftCode: copying the Gauge trace from \(remote.settings.destination)\n", kind: .debugger)
                    let products = appURL.deletingLastPathComponent()
                    Task { [weak self] in
                        let result: Result<URL, Error> = await Task.detached {
                            do {
                                try remote.fetchProfile(profile)
                                try Self.symbolicateTrace(at: profile.localURL, searching: [products])
                                return .success(profile.localURL)
                            } catch {
                                return .failure(error)
                            }
                        }.value
                        if case .failure(let e) = result { self?.appendConsole("SwiftCode: Gauge: \(e)\n", kind: .debugger) }
                        onTrace?(result)
                    }
                }
            })
        } catch {
            appendConsole("SwiftCode: \(error)\n")
            simulatorRun = nil
            fail("ssh did not start: \(error)")
        }
    }
}

extension WorkspaceSession {
    func attachToRemoteSimulatorApp(_ state: SimulatorRunState, remote: RemoteSimulator, app appURL: URL, device: String) async {
        guard let app = AppBundle(url: appURL), let port = RemoteSimulator.freeLoopbackPort() else { return }
        runningProduct = app.executable
        runningDeviceName = device
        let forward = Process()
        forward.executableURL = URL(fileURLWithPath: remote.settings.ssh)
        forward.arguments = remote.debugForwardArguments(localPort: port)
        forward.standardInput = FileHandle.nullDevice
        forward.standardOutput = FileHandle.nullDevice
        forward.standardError = FileHandle.nullDevice
        do { try forward.run() } catch {
            appendConsole("SwiftCode: the debugger's ssh forward did not start: \(error)\n", kind: .debugger)
            return
        }
        state.debugForward = forward
        for _ in 0..<100 where forward.isRunning {
            if await Task.detached(operation: { Self.portAccepts(port) }).value { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard forward.isRunning, simulatorRun === state, !state.stopRequested else {
            if forward.isRunning { forward.terminate() }
            appendConsole("SwiftCode: the debugger could not reach \(remote.settings.destination)\n", kind: .debugger)
            if simulatorRun === state { setActivity(.running(WorkspaceSession.RunActivityText.running(app.executable, on: device))) }
            return
        }
        guard let path = await Task.detached(operation: { LLDBDAP.locate() }).value else {
            appendConsole("SwiftCode: lldb-dap was not found.\n")
            forward.terminate()
            return
        }
        do {
            let client = try DAPClient(transport: ProcessTransport(executable: path))
            debugClient = client
            Task { [weak self] in
                for await e in client.events { await self?.handle(e) }
                self?.sessionEnded()
                if forward.isRunning { forward.terminate() }
            }
            try await client.initialize()
            attachingSimulatorApp = true
            defer { attachingSimulatorApp = false }
            let dir = app.executableURL.deletingLastPathComponent().path
            try await client.attachRemote(port: port, program: app.executableURL.path, threadFormat: DebugThread.format,
                                          preRunCommands: RemoteSimulator.debuggerSettings(appDirectory: dir))
            for _ in 0..<100 where stoppedThread == nil { try? await Task.sleep(for: .milliseconds(100)) }
            attachingSimulatorApp = false
            if stoppedThread != nil { await continueOrPause() }
        } catch {
            appendConsole("SwiftCode: attach failed: \(error)\n")
            if forward.isRunning { forward.terminate() }
        }
        if simulatorRun === state, case .running = activity, stoppedThread == nil {
            setActivity(.running(WorkspaceSession.RunActivityText.running(app.executable, on: device)))
        }
    }

    nonisolated static func portAccepts(_ port: Int) -> Bool {
        let fd = socket(AF_INET, RemoteSimulator.streamSocketType, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = UInt16(port).bigEndian
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } == 0
    }
}

public struct RemoteRunFailure: Error, CustomStringConvertible, Sendable {
    public var description: String
}

extension WorkspaceSession {
    nonisolated static func symbolicateTrace(at url: URL, searching roots: [URL]) throws {
        var t = try GaugeTraceCodec.read(url)
        GaugeSymbolicator.symbolicateMachO(&t, searching: roots)
        GaugeSymbolicator.demangle(&t)
        try GaugeTraceCodec.write(t, to: url)
    }
}

extension WorkspaceSession {
    public func controlRemoteSimulator(remote: RemoteSimulator, _ words: [String]) async -> (Bool, String) {
        guard remote.settings.isConfigured else { return (false, "Set the remote simulator in Settings ▸ Simulators first.") }
        let (status, output) = await Task.detached { remote.control(words) }.value
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.first != "state" && words.first != "settings" { appendConsole("SwiftCode: \(words.joined(separator: " ")): \(text)\n", kind: .debugger) }
        return (status == 0, text)
    }

    public func eraseRemoteSimulator(remote: RemoteSimulator) async -> (Bool, String) {
        guard remote.settings.isConfigured else { return (false, "Set the remote simulator in Settings ▸ Simulators first.") }
        if case .remote = simulatorRun?.target { return (false, "Stop the run on \(RemoteSimulator.deviceName) before erasing it.") }
        appendConsole("SwiftCode: erasing \(RemoteSimulator.deviceName) (\(remote.remoteDevicePath) on \(remote.settings.destination))\n", kind: .debugger)
        let (status, output) = await Task.detached { remote.erase() }.value
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { appendConsole(text + "\n", kind: .debugger) }
        guard status == 0 else {
            let last = text.split(separator: "\n").last.map(String.init) ?? ""
            return (false, "Erase failed (status \(status))" + (last.isEmpty ? "" : ": \(last)"))
        }
        return (true, "Erased")
    }
}
