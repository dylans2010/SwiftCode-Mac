import Foundation

public enum SetupCheckState: String, Sendable, Equatable, Codable {
    case ok, missing, unknown
    case notApplicable = "na"

    public var title: String {
        switch self {
        case .ok: "Passed"
        case .missing: "Needs attention"
        case .unknown: "Unknown"
        case .notApplicable: "Not applicable"
        }
    }
}

public enum RuntimeImportTool: String, Sendable, Equatable, CaseIterable {
    case simctl, xcodebuild

    public func command(file: String) -> [String] {
        switch self {
        case .simctl: ["xcrun", "simctl", "runtime", "add", file]
        case .xcodebuild: ["xcodebuild", "-importPlatform", file]
        }
    }
}

public enum RuntimeAction: Sendable, Equatable {
    case importImage(path: String, tool: RuntimeImportTool)
    case copyToThisMachine(source: String, record: SimRuntimeRecord)
    case copyToHost(source: String, record: SimRuntimeRecord, host: String)
    case remove(SimRuntimeRecord)
    case provisionApply
    case downloadWithXcode(XcodebuildDownload)
    case downloadDirect(RuntimeRequest)
    case installDecryptor
}

public enum RuntimeFix: Sendable, Equatable {
    case command(String)
    case action(RuntimeAction)
    case instructions(String)
    case step(RuntimeSetupStep)
}

public struct RuntimeCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var state: SetupCheckState
    public var reason: String
    public var fix: RuntimeFix?

    public init(_ id: String, _ title: String, _ state: SetupCheckState, _ reason: String, fix: RuntimeFix? = nil) {
        self.id = id
        self.title = title
        self.state = state
        self.reason = reason
        self.fix = fix
    }

    public static func runtimeID(_ p: SimPlatform, host: Bool = false) -> String { (host ? "host.runtime." : "runtime.") + p.rawValue }
}

public enum RuntimeTarget: Sendable, Equatable {
    case thisMachine
    case host(RuntimeHostSettings)

    public var isHost: Bool { if case .host = self { true } else { false } }
}

public struct SetupMachine: Sendable, Equatable {
    public var isMac: Bool
    public var architecture: String
    public init(isMac: Bool, architecture: String) {
        self.isMac = isMac
        self.architecture = architecture
    }

    public var isARM64: Bool { ["arm64", "aarch64"].contains(architecture) }
    public var canRunSimulatorHere: Bool { isMac || isARM64 }

    public static var current: SetupMachine {
        var u = utsname()
        uname(&u)
        let arch = withUnsafePointer(to: &u.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
        #if os(macOS)
        return SetupMachine(isMac: true, architecture: arch)
        #else
        return SetupMachine(isMac: false, architecture: arch)
        #endif
    }

    public var title: String { isMac ? "This Mac" : "This computer" }
}

public enum RuntimeSetupStep: Int, Sendable, CaseIterable, Codable {
    case target, runtimes, add, host, prepare, finish, download

    public var title: String {
        switch self {
        case .target: "Where to Run"
        case .runtimes: "Runtimes"
        case .add: "Add a Runtime"
        case .host: "Simulator Host"
        case .prepare: "Prepare Host"
        case .finish: "Ready"
        case .download: "Get a Runtime"
        }
    }

    public func summary(machine: SetupMachine, target: RuntimeTarget) -> String {
        switch self {
        case .target:
            return "Choose the platforms you build for and where their simulators run. SwiftCode uses the runtimes you have, or gets one from Apple when you ask."
        case .runtimes:
            if target.isHost { return "The runtimes on the simulator host, and the ones here that can be copied to it." }
            return machine.isMac ? "The simulator runtimes registered on this Mac. Runtimes that Xcode installed are listed here; manage them in Xcode."
                : "The runtimes in SwiftCode's folder on this computer. SwiftCode's simulator boots a runtime's RuntimeRoot."
        case .add:
            if target.isHost { return "Copy a runtime you have to the simulator host. A copy that stops resumes where it left off." }
            return machine.isMac ? "Add a runtime disk image you downloaded yourself. SwiftCode shows the command and runs it only when you confirm."
                : "Copy a runtime bundle or RuntimeRoot from your own Xcode installation into SwiftCode's folder."
        case .host:
            return "The arm64 Linux machine with KVM that runs the simulator. SwiftCode logs in with an ssh key and pairs over its own link."
        case .prepare:
            return "A setup script for the host. It only reports until you choose to apply it. Steps that need root run in your own terminal with sudo."
        case .finish:
            return "What is ready, and the run destinations it gives you."
        case .download:
            return machine.isMac ? "Get a runtime from Apple: with Xcode's own tool, or downloaded by SwiftCode. Each starts only after you confirm, and Cancel stops it."
                : "Get a runtime from Apple: SwiftCode downloads it for you, checks it and puts its RuntimeRoot in its folder. It starts only after you confirm."
        }
    }

    public static func steps(for target: RuntimeTarget) -> [RuntimeSetupStep] {
        target.isHost ? [.target, .host, .prepare, .runtimes, .download, .add, .finish] : [.target, .runtimes, .download, .add, .finish]
    }

    public func shows(_ check: RuntimeCheck) -> Bool {
        switch self {
        case .target: ["machine", "tools", "kvm"].contains(check.id)
        case .runtimes: check.id.hasPrefix("runtime.") || check.id.hasPrefix("host.runtime.")
        case .add: ["disk", "host.disk", "transfer"].contains(check.id)
        case .host: check.id.hasPrefix("host.") && !check.id.hasPrefix("host.runtime.") && check.id != "host.disk"
        case .prepare: check.id.hasPrefix("setup.")
        case .finish: false
        case .download: check.id.hasPrefix("download.")
        }
    }
}

public struct RuntimeSetupReport: Sendable, Equatable {
    public var checks: [RuntimeCheck]
    public var local: [SimRuntimeRecord]
    public var host: [SimRuntimeRecord]

    public init(checks: [RuntimeCheck] = [], local: [SimRuntimeRecord] = [], host: [SimRuntimeRecord] = []) {
        self.checks = checks
        self.local = local
        self.host = host
    }

    public func check(_ id: String) -> RuntimeCheck? { checks.first { $0.id == id } }
    public func checks(in step: RuntimeSetupStep) -> [RuntimeCheck] { checks.filter(step.shows) }

    public func state(of step: RuntimeSetupStep) -> SetupCheckState? {
        let cs = checks(in: step)
        guard !cs.isEmpty else { return nil }
        if cs.allSatisfy({ $0.state == .ok || $0.state == .notApplicable }) { return .ok }
        return cs.contains { $0.state == .missing } ? .missing : .unknown
    }

    public var readyPlatforms: [SimPlatform] {
        SimPlatform.allCases.filter { p in
            checks.contains { ($0.id == RuntimeCheck.runtimeID(p) || $0.id == RuntimeCheck.runtimeID(p, host: true)) && $0.state == .ok }
        }
    }

    public func firstProblemStep(for target: RuntimeTarget) -> RuntimeSetupStep {
        for s in RuntimeSetupStep.steps(for: target) where s != .target && state(of: s) == .missing { return s }
        return readyPlatforms.isEmpty ? .runtimes : .finish
    }
}

public struct RuntimeSetupChoices: Sendable, Equatable, Codable {
    public var platforms: Set<SimPlatform> = [.iOS]
    public var minimumVersions: [SimPlatform: String] = [:]
    public var useHost = false
    public var host = RuntimeHostSettings()

    public init() {}

    static let key = "SwiftCode.runtimeSetup.choices"
    public static let offeredKey = "SwiftCode.runtimeSetup.offered"

    public static func load(_ d: UserDefaults) -> RuntimeSetupChoices {
        guard let data = d.data(forKey: key), let c = try? JSONDecoder().decode(RuntimeSetupChoices.self, from: data) else { return RuntimeSetupChoices() }
        return c
    }

    public func save(_ d: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.key) }
    }

    public var target: RuntimeTarget { useHost ? .host(host) : .thisMachine }
}

public struct RuntimeSetupChecker: Sendable {
    public var machine: SetupMachine
    public var choices: RuntimeSetupChoices
    public var runner: any HeadsetCommandRunner
    public var folder: String

    public init(machine: SetupMachine = .current, choices: RuntimeSetupChoices, runner: any HeadsetCommandRunner = LocalHeadsetRunner(timeout: 60),
                folder: String = RuntimeFolders.local()) {
        self.machine = machine
        self.choices = choices
        self.runner = runner
        self.folder = folder
    }

    public enum Command {
        public static let simctlHelp = "xcrun --find simctl"
        public static let images = "xcrun simctl runtime list -j"
        public static let runtimes = "xcrun simctl list runtimes -j"
        public static let kvm = "if [ -c /dev/kvm ]; then if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then echo access; else echo denied; fi; else echo absent; fi"
        public static func freeKB(_ path: String) -> String {
            "p=\(path.shellQuoted); while [ ! -e \"$p\" ] && [ \"$p\" != / ]; do p=$(dirname \"$p\"); done; df -Pk \"$p\" | awk 'NR==2 {print $4}'"
        }
    }

    public func run() async -> RuntimeSetupReport {
        var report = RuntimeSetupReport()
        report.checks.append(checkMachine())
        if machine.isMac {
            let tools = await checkTools()
            report.checks.append(tools)
            if tools.state == .ok { report.local = await readCoreSimulator() }
        } else if machine.isARM64 {
            report.checks.append(await checkKVM())
        }
        report.local += RuntimeBundleReader.swiftcodeRuntimes(in: folder)
        if !choices.useHost {
            for p in SimPlatform.allCases where choices.platforms.contains(p) {
                report.checks.append(Self.checkRuntime(p, records: report.local, minimum: choices.minimumVersions[p], machine: machine, host: nil))
            }
            report.checks.append(await checkDisk())
        }
        return report
    }

    func checkMachine() -> RuntimeCheck {
        if machine.isMac { return RuntimeCheck("machine", "This Mac", .ok, "Simulators run here with the runtimes registered with CoreSimulator.") }
        if machine.isARM64 { return RuntimeCheck("machine", "This computer", .ok, "arm64 Linux: SwiftCode's simulator can run here with KVM.") }
        if choices.useHost {
            return RuntimeCheck("machine", "This computer", .ok, "\(machine.architecture) Linux: the simulator runs on the host you choose.")
        }
        return RuntimeCheck("machine", "This computer", .missing,
                            "SwiftCode's simulator needs arm64 Linux with KVM; this computer is \(machine.architecture). Run it on another machine.",
                            fix: .step(.host))
    }

    func checkTools() async -> RuntimeCheck {
        let r = await runner.run(Command.simctlHelp)
        if r.ok { return RuntimeCheck("tools", "Simulator tools", .ok, "simctl from your Xcode (\(r.output.trimmed)).") }
        return RuntimeCheck("tools", "Simulator tools", .missing, "simctl was not found. Install Xcode, open it once, and choose it as the developer directory.",
                            fix: .command("xcodebuild -runFirstLaunch"))
    }

    func readCoreSimulator() async -> [SimRuntimeRecord] {
        let images = await runner.run(Command.images)
        let listed = await runner.run(Command.runtimes)
        guard images.ok else { return listed.ok ? SimctlRuntimeListing.parseRuntimes(Data(listed.output.utf8)) : [] }
        return SimctlRuntimeListing.parse(images: Data(images.output.utf8), runtimes: listed.ok ? Data(listed.output.utf8) : nil)
    }

    func checkKVM() async -> RuntimeCheck {
        let r = await runner.run(Command.kvm)
        switch r.output.trimmed {
        case "access": return RuntimeCheck("kvm", "KVM", .ok, "/dev/kvm is open to you.")
        case "denied": return RuntimeCheck("kvm", "KVM", .missing, "/dev/kvm exists, but you may not open it.", fix: .command("sudo usermod -aG kvm $USER"))
        case "absent": return RuntimeCheck("kvm", "KVM", .missing, "This computer has no /dev/kvm: turn on virtualization, or run the simulator on another machine.",
                                           fix: .step(.host))
        default: return RuntimeCheck("kvm", "KVM", .unknown, "Could not look at /dev/kvm.")
        }
    }

    func checkDisk() async -> RuntimeCheck {
        let path = machine.isMac ? "/" : folder
        let need = choices.platforms.map { machine.isMac ? $0.typicalImageBytes : $0.typicalUnpackedBytes }.max() ?? 0
        return Self.diskCheck(id: "disk", title: "Disk space", output: await runner.run(Command.freeKB(path)), needBytes: need,
                              place: machine.isMac ? "the system volume" : folder)
    }

    public static func diskCheck(id: String, title: String, output r: HeadsetCommandResult, needBytes: Int64, place: String) -> RuntimeCheck {
        guard r.ok, let kb = Int64(r.output.trimmed) else { return RuntimeCheck(id, title, .unknown, "Could not read the free space of \(place).") }
        let free = kb * 1024
        if free >= needBytes { return RuntimeCheck(id, title, .ok, "\(RuntimeSize.format(free)) free on \(place).") }
        return RuntimeCheck(id, title, .missing,
                            "\(RuntimeSize.format(free)) free on \(place); a runtime needs about \(RuntimeSize.format(needBytes)).",
                            fix: .instructions("Free some space, or remove a runtime you no longer use."))
    }

    public static func checkRuntime(_ p: SimPlatform, records: [SimRuntimeRecord], minimum: String?, machine: SetupMachine, host: String?) -> RuntimeCheck {
        let id = RuntimeCheck.runtimeID(p, host: host != nil)
        let title = "Runtime for \(p.title)"
        let mine = records.filter { $0.platform == p }
        let usable = mine.filter(\.isUsable)
        let fitting = usable.filter { r in minimum.map { SimRuntimeRecord.compareVersions(r.version, $0) != .orderedAscending } ?? true }
        if let best = SimctlRuntimeListing.sorted(fitting).first {
            let more = fitting.count > 1 ? " and \(fitting.count - 1) more" : ""
            return RuntimeCheck(id, title, .ok, "\(best.title), \(best.sizeText)\(more).")
        }
        if let newest = SimctlRuntimeListing.sorted(usable).first, let minimum {
            return RuntimeCheck(id, title, .missing, "The newest is \(p.title) \(newest.version), older than the deployment target \(minimum). Get a newer runtime or lower the target.",
                                fix: .step(.download))
        }
        if let bad = mine.first {
            let why = bad.availabilityError ?? "its state is \(bad.state)"
            let fix: RuntimeFix = bad.isRemovable ? .action(.remove(bad)) : .instructions("Delete it in the IDE that installed it and add it again.")
            return RuntimeCheck(id, title, .missing, "\(bad.title) cannot be used: \(why).", fix: fix)
        }
        let whereText = host.map { "on \($0)" } ?? (machine.isMac ? "on this Mac" : "in SwiftCode's folder")
        return RuntimeCheck(id, title, .missing, "No \(p.title) runtime \(whereText).", fix: .step(.download))
    }

    public static func acquisitionNote(_ p: SimPlatform) -> String {
        "Get a Runtime downloads one from Apple when you ask: with Xcode on a Mac (xcodebuild -downloadPlatform \(p.downloadName)), or with SwiftCode's own download. A runtime you already have is added here."
    }
}

public struct RuntimeConfirmation: Sendable, Equatable {
    public var title: String
    public var message: String
    public var command: String
    public var confirmTitle: String
    public var isDestructive: Bool
    public var action: RuntimeAction

    public init(title: String, message: String, command: String, confirmTitle: String, isDestructive: Bool = false, action: RuntimeAction) {
        self.title = title
        self.message = message
        self.command = command
        self.confirmTitle = confirmTitle
        self.isDestructive = isDestructive
        self.action = action
    }
}

public enum RuntimeCommands {
    public static func line(_ argv: [String]) -> String { argv.map(\.shellQuoted).joined(separator: " ") }

    public static func copyLocal(source: String, folder: String, record: SimRuntimeRecord, markerJSON: String, rsync: String = "rsync") -> String {
        let dest = folder + "/" + record.folderName
        let incoming = dest + RuntimeFolders.incomingSuffix
        return "mkdir -p \(incoming.shellQuoted)/RuntimeRoot && \(rsync) -a --partial \((source + "/").shellQuoted) \((incoming + "/RuntimeRoot/").shellQuoted)"
            + " && printf '%s\\n' \(markerJSON.shellQuoted) > \((incoming + "/" + RuntimeFolders.marker).shellQuoted)"
            + " && rm -rf \(dest.shellQuoted) && mv \(incoming.shellQuoted) \(dest.shellQuoted)"
    }

    public static func remove(path: String, folder: String) -> String? {
        guard RuntimeFolders.isRuntimeFolder(path, inside: folder) else { return nil }
        let p = path.shellQuoted
        return "test -f \(p)/\(RuntimeFolders.marker) && rm -rf \(p)"
    }
}
