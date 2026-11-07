#if os(Linux) && arch(arm64)
import Foundation
import Glibc
import SwiftCodeDarwinABI
import SwiftCodeDarwinKernel
import SwiftCodeDisplayStream
import SwiftCodeHypervisor
import SwiftCodeMachO
import SwiftCodeHostServices
import SwiftCodeSimFeatures
import SwiftCodeMetalHost
import SwiftCodeVulkan

final class ExecConfiguration: @unchecked Sendable {
    static let rootDevice: UInt32 = 0x0100_0010
    static let firstPrefixDevice: UInt32 = 0x0100_0011
    let options: Options
    let trace: Bool
    let execPath: String
    let root: String
    let dyldSimPath: String
    let shim: [UInt8]
    let stubs: [UInt8]
    let runDir: String
    let runDirToRemove: String?
    let prefixes: [DarwinFileSystem.Prefix]
    let hostLibraryPaths: Set<String>
    let cacheIndex: SharedCacheIndex
    let cacheImageFiles: CacheImageFiles?
    let maxExits: Int
    let timeout: UInt64
    var quietRuns = false
    let device: DeviceLayout?
    private(set) var camera: DeviceCamera?
    let rootArguments: [String]
    let rootEnvironment: [String]

    init(_ options: Options) throws {
        let macOSRoot = MacOSMode.enabled ? MacOSMode.locateRoot(explicit: options.macOSRoot) : nil
        guard let rootArgument = macOSRoot ?? options.runtimeRoot, options.execPath != nil || options.devicePath != nil else {
            die("--exec and --device need --runtime-root\n\(usage)", status: 64)
        }
        if options.execPath != nil && options.devicePath != nil { die("--exec and --device exclude each other", status: 64) }
        self.options = options
        trace = options.trace
        timeout = options.timeoutMilliseconds ?? 120_000
        maxExits = options.maxExits ?? 50_000_000
        var root = absolutePath(rootArgument)
        while root.count > 1 && root.hasSuffix("/") { root.removeLast() }
        self.root = root
        if let devicePath = options.devicePath {
            var layout = DeviceLayout(dev: absolutePath(devicePath), runtimeRoot: root, udid: options.udid,
                                      jobPaths: options.jobPaths.map(absolutePath), runtimePaths: options.runtimePaths,
                                      oneshots: options.oneshots, runtimeJobs: options.runtimeJobs)
            layout.plistBoolOverrides = options.plistBoolOverrides
            let platform = layout.runtimePlatform()
            let recorded = DeviceLayout.recordedDeviceType(in: layout.dev).flatMap(DeviceType.named).flatMap { $0.platform == platform ? $0 : nil }
            layout.deviceType = options.deviceType ?? recorded ?? DeviceType.default(for: platform, version: layout.runtimeVersion().version)
            layout.lean = LeanBootProfile.fromProcessEnvironment(platform: platform)
            layout.oneshotDelay = options.oneshotDelay
            layout.installApp = options.installApp.map(absolutePath)
            layout.launchBundleID = options.launchBundleID
            layout.appArguments = options.appArguments
            layout.appURL = options.appURL
            layout.appEnvironment = options.appEnvironment
            if options.framebufferLibrary != "none" {
                let fallback = options.shimPath.map { shim -> String in
                    let simShim = ((absolutePath(shim) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
                    return ((simShim as NSString).deletingLastPathComponent as NSString)
                        .appendingPathComponent("SimGuestFrameworks/out/SimFramebuffer.framework/SimFramebuffer")
                }
                layout.framebufferLibrary = options.framebufferLibrary.map(absolutePath)
                    ?? fallback.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
            }
            layout.hidBundle = hidBundlePath(options, foldable: layout.deviceType.isFoldable || layout.deviceType.family == .watch
                                                 || layout.deviceType.family == .vision)
            if let room = options.visionRoom {
                guard layout.deviceType.family == .vision else { die("--room: \(layout.deviceType.name) is not a Vision Pro", status: 64) }
                do {
                    try VisionRooms.writePreference(dev: layout.dev, room: room)
                    stderrLine("swiftcode-simd: visionOS: room \(room) for this boot (\(VisionRooms.preferenceKey))")
                } catch {
                    die("--room: cannot write \(VisionRooms.preferencePath(dev: layout.dev)): \(error)", status: 73)
                }
            }
            let agentsOut = options.shimPath.map { shim -> String in
                let simShim = ((absolutePath(shim) as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
                return ((simShim as NSString).deletingLastPathComponent as NSString).appendingPathComponent("SimGuestAgents/out")
            }
            func guestAgentFile(_ name: String) -> String? {
                [options.guestTools.map(absolutePath), agentsOut].compactMap { $0 }.map { $0 + "/" + name }
                    .first { FileManager.default.fileExists(atPath: $0) }
            }
            layout.settingsAgent = options.settingsAgent == "none" ? nil
                : options.settingsAgent.map(absolutePath) ?? guestAgentFile("swiftcode-settings-agent")
            layout.pairingAgent = options.pairingAgent == "none" ? nil
                : options.pairingAgent.map(absolutePath) ?? guestAgentFile("swiftcode-pairing-agent")
            layout.healthAgent = options.healthAgent == "none" ? nil
                : options.healthAgent.map(absolutePath) ?? guestAgentFile(DeviceLayout.healthAgentBundleName)
            if options.environmentOverrides {
                layout.overridesLibrary = guestAgentFile("libSwiftCodeEnvironmentOverrides.dylib")
                if layout.overridesLibrary == nil {
                    stderrLine("swiftcode-simd: warning: --environment-overrides: no libSwiftCodeEnvironmentOverrides.dylib in the guest tools")
                }
            }
            if let profile = options.profile, profile.signposts, options.launchBundleID != nil {
                layout.gaugeLibrary = guestAgentFile(GaugeAgentFiles.libraryName)
                if layout.gaugeLibrary == nil {
                    stderrLine("swiftcode-simd: warning: --profile: no \(GaugeAgentFiles.libraryName) in the guest tools; the trace has no signposts")
                }
            }
            layout.skipFirstBootMigration = options.skipFirstBootMigration
            layout.restoring = !(ProcessInfo.processInfo.environment["SWIFTCODE_RESTORE_DIR"] ?? "").isEmpty
            layout.guestTools = options.guestTools.map(absolutePath)
                ?? options.shimPath.map { ((absolutePath($0) as NSString).deletingLastPathComponent as NSString)
                    .appendingPathComponent("guest-tests/stage7") }
            layout.guestDev = layout.resolveGuestDevicePath()
            for (what, path) in [("device directory", layout.dev), ("runtime root", root)] + layout.jobPaths.map({ ("job path", $0) }) {
                for shadowed in ["/tmp", "/var", "/etc", "/private/tmp", "/private/var", "/private/etc"]
                    where path == shadowed || path.hasPrefix(shadowed + "/") {
                    die("the \(what) \(path) is under \(shadowed), which the guest sees as its own; put it elsewhere", status: 64)
                }
            }
            do { try layout.prepare() } catch { die("cannot prepare the device directory \(layout.dev): \(error)", status: 66) }
            layout.appEnvironment += layout.overridesEnvironment
            layout.appEnvironment = DeviceLayout.mergingInsertedLibraries(layout.appEnvironment, layout.gaugeEnvironment)
            if let profile = options.profile {
                let r = GaugeRecorder(options: profile)
                r.appExecutable = options.installApp.flatMap { app -> String? in
                    let plist = absolutePath(app) + "/Info.plist"
                    guard let data = FileManager.default.contents(atPath: plist),
                          let p = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
                    return p["CFBundleExecutable"] as? String
                }
                r.signpostsHostPath = layout.gaugeLibrary != nil ? layout.gaugeSignpostsHostPath : nil
                r.frameRecordPath = layout.framebufferStatePath
                let v = layout.runtimeVersion()
                r.deviceDescription = "\(layout.deviceType.name), iOS \(v.version) (\(v.build)), SwiftCode simulator"
                r.command = options.launchBundleID ?? r.appExecutable ?? ""
                if getenv("SWIFTCODE_METAL_TRACE") == nil && getenv("SWIFTCODE_GAUGE_GPU").map({ String(cString: $0) }) != "0" {
                    setenv("SWIFTCODE_METAL_TRACE", profile.path + ".metal", 1)
                }
                r.metalTracePath = getenv("SWIFTCODE_METAL_TRACE").map { String(cString: $0) }
                GaugeRecorder.shared = r
            }
            device = layout
            camera = DeviceCamera(options: options, layout: layout)
            execPath = layout.launchdSimPath
            rootArguments = ["launchd_sim", layout.guestPath(layout.plistPath)] + options.execArguments
            rootEnvironment = layout.launchdEnvironment(overrides: options.environment)
            let t = layout.deviceType
            if let bytes = ProcessInfo.processInfo.environment["SWIFTCODE_GUEST_MEMSIZE"].flatMap(UInt64.init) {
                Stage3Layout.memorySize = bytes
                stderrLine("swiftcode-simd: guest memory size \(bytes >> 20) MiB")
            }
            stderrLine("swiftcode-simd: device type \(t.id) (\(t.name), \(t.modelIdentifier), \(t.screen.width)x\(t.screen.height) @\(Int(t.screen.scale)))")
            stderrLine("swiftcode-simd: device \(layout.dev)\(layout.guestDev == layout.dev ? "" : " (guest path \(layout.guestDev))"), UDID \(layout.udid); bootstrap plist \(layout.plistPath); TMP \(layout.tmpGuestPath) -> \(layout.tmpHostPath)")
        } else {
            device = nil
            execPath = absolutePath(options.execPath!)
            rootArguments = [execPath] + options.execArguments
            var env = MacOSMode.enabled ? MacOSMode.environment() : SimulatorEnvironment.make(runtimeRoot: root)
            for pair in options.environment {
                let key = pair.prefix { $0 != "=" }
                env.removeAll { $0.hasPrefix(key + "=") }
                env.append(pair)
            }
            rootEnvironment = env
        }
        dyldSimPath = root + (MacOSMode.enabled ? MacOSMode.dyldGuestPath : "/usr/lib/dyld_sim")
        let index = SharedCacheIndex(cachePath: MacOSMode.enabled ? "" : root + "/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64")
        cacheIndex = index
        cacheImageFiles = CacheImageFiles.enabledByEnvironment
            ? CacheImageFiles(runtimeRoot: root, imagePaths: { index.imagePaths() }) : nil
        for path in [execPath, dyldSimPath] where access(path, R_OK) != 0 {
            die("cannot read \(path): \(String(cString: strerror(errno)))", status: 66)
        }
        shim = readFile(locateSimShimFile("shim.bin", explicit: options.shimPath))
        stubs = readFile(locateSimShimFile("host_stubs.bin", explicit: options.hostStubsPath))
        guard !shim.isEmpty, UInt64(shim.count) <= VMLayout.shimRegionSize else { die("bad shim image", status: 66) }
        guard UInt64(stubs.count) == VMLayout.hostPageSize else {
            die("host_stubs.bin is \(stubs.count) bytes, expected \(VMLayout.hostPageSize)", status: 66)
        }
        let retWord = stubs.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: Int(hostPageRetStubOffset), as: UInt32.self)) }
        guard retWord == a64Ret else { die("host_stubs.bin has no `ret` at +\(hex(hostPageRetStubOffset))", status: 66) }

        runDir = device.map { $0.data } ?? absolutePath(options.runDir ?? (NSTemporaryDirectory() + "/swiftcode-simd-\(getpid())"))
        let usesDefaultRunDir = device == nil && options.runDir == nil
        let runDirExisted = FileManager.default.fileExists(atPath: runDir)
        try FileManager.default.createDirectory(atPath: runDir + "/tmp", withIntermediateDirectories: true)
        runDirToRemove = usesDefaultRunDir && !runDirExisted && !options.keepRunDir ? runDir : nil

        let execDirectory = (execPath as NSString).deletingLastPathComponent
        var prefixes = [DarwinFileSystem.Prefix(guestPath: MacOSMode.enabled ? "/" : root, hostPath: root, writable: false)]
        if !execDirectory.hasPrefix(root + "/") {
            prefixes.append(DarwinFileSystem.Prefix(guestPath: execDirectory, hostPath: execDirectory, writable: false))
        }
        if let device {
            prefixes[0].ownerUID = 0
            prefixes[0].ownerGID = 80
            DarwinKernel.setPlatformCodeRoots([root])
            DarwinKernel.simulatorPlatform = device.runtimePlatform().machOPlatform
            prefixes.append(DarwinFileSystem.Prefix(guestPath: device.guestDev, hostPath: device.dev, writable: true))
            VolumeMetadata.documentIDStateDirectory = device.data
            prefixes.append(DarwinFileSystem.Prefix(guestPath: "/System", hostPath: root + "/System", writable: false,
                                                    ownerUID: 0, ownerGID: 0))
            for path in device.jobPaths where !(path == device.dev || path.hasPrefix(device.dev + "/") || path == root || path.hasPrefix(root + "/")) {
                prefixes.append(DarwinFileSystem.Prefix(guestPath: path, hostPath: path, writable: false))
            }
            prefixes.append(DarwinFileSystem.Prefix(guestPath: "/private/var/tmp", hostPath: device.privateVarTmpHostPath, writable: true))
            prefixes.append(DarwinFileSystem.Prefix(guestPath: "/private/tmp", hostPath: device.data + "/tmp", writable: true))
            prefixes.append(DarwinFileSystem.Prefix(guestPath: device.memoryGuestPath, hostPath: device.memoryHostPath, writable: true))
            if GuestNetwork.enabled, let resolv = realpath("/etc/resolv.conf", nil) {
                prefixes.append(DarwinFileSystem.Prefix(guestPath: "/private/etc/resolv.conf", hostPath: String(cString: resolv),
                                                        writable: false, ownerUID: 0, ownerGID: 0))
                free(resolv)
            }
        }
        var hostLibraryPaths: Set<String> = []
        let (hostLibDir, hostLibTried) = locateHostLibraryDirectory(explicit: options.hostLibsPath)
        if MacOSMode.enabled {
            DarwinKernel.simulatorPlatform = MacOSMode.platform
            hostLibraryPaths = Set(hostLibraryNames.map(hostLibraryGuestPath))
        } else if let hostLibDir {
            let platform = device?.runtimePlatform() ?? .iOS
            for name in hostLibraryNames {
                var file = "\(hostLibDir)/libsystem_\(name).dylib"
                let guest = hostLibraryGuestPath(name)
                if let device, platform != .iOS, access(file, R_OK) == 0 {
                    do {
                        file = try GuestImagePlatform.adaptedCopy(of: file, to: device.dev + "/swiftcode-frameworks/host-libs/libsystem_\(name).dylib",
                                                                  for: platform, version: device.runtimeVersion().version)
                    } catch { die("cannot adapt the host library \(file) to \(platform.displayName): \(error)", status: 66) }
                }
                if access(file, R_OK) == 0 {
                    prefixes.append(DarwinFileSystem.Prefix(guestPath: guest, hostPath: file, writable: false,
                                                            ownerUID: device == nil ? nil : 0, ownerGID: device == nil ? nil : 80))
                    hostLibraryPaths.insert(guest)
                    stderrLine("swiftcode-simd: host library \(guest) -> \(file)")
                } else {
                    stderrLine("swiftcode-simd: warning: host library \(file) is missing; \(guest) will be ENOENT")
                }
            }
        } else {
            stderrLine("swiftcode-simd: warning: no host-library directory (tried \(hostLibTried.joined(separator: ", "))); pass --host-libs")
        }
        if device == nil {
            prefixes.append(DarwinFileSystem.Prefix(guestPath: "/tmp", hostPath: runDir + "/tmp", writable: true))
        } else {
            for i in prefixes.indices {
                let isDirectory = (try? FileManager.default.attributesOfItem(atPath: prefixes[i].hostPath)[.type]
                    as? FileAttributeType) == .typeDirectory
                if !isDirectory || prefixes[i].guestPath == root {
                    prefixes[i].device = Self.firstPrefixDevice
                } else {
                    prefixes[i].device = Self.rootDevice
                    prefixes[i].mountPoint = "/"
                }
            }
        }
        self.prefixes = prefixes
        self.hostLibraryPaths = hostLibraryPaths
    }

    func makeRootFileSystem() -> DarwinFileSystem {
        let fs = DarwinFileSystem(prefixes: prefixes, console: { fd, bytes in writeFD(fd == 2 ? 2 : 1, bytes) })
        fs.cacheImageFiles = cacheImageFiles
        if device != nil {
            fs.rootDevice = Self.rootDevice
            fs.guestSymlinks = DarwinFileSystem.darwinRootSymlinks
            do {
                try fs.installDeviceModeStandardDescriptors()
            } catch {
                stderrLine("swiftcode-simd: warning: cannot set up fds 0, 1, 3 from /dev (\(error)); fds 0-2 stay the console")
            }
            fs.cwd = "/"
        }
        return fs
    }

    var rootRequest: ProcessImageRequest {
        ProcessImageRequest(executablePath: execPath, hostExecutablePath: execPath, argv: rootArguments,
                            envp: rootEnvironment)
    }
}

struct HostStats: CustomStringConvertible {
    var threads = 0
    var rssKiB = 0
    var fds = 0

    static func current() -> HostStats {
        var stats = HostStats()
        if let text = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 2 else { continue }
                if parts[0] == "Threads:" { stats.threads = Int(parts[1]) ?? 0 }
                if parts[0] == "VmRSS:" { stats.rssKiB = Int(parts[1]) ?? 0 }
            }
        }
        stats.fds = max(0, ((try? FileManager.default.contentsOfDirectory(atPath: "/proc/self/fd"))?.count ?? 1) - 1)
        return stats
    }

    var description: String {
        let vms = VMCounters.shared.snapshot
        let deferred = VCPUPool.deferredCreations.load(ordering: .relaxed)
        let deferredNs = VCPUPool.deferredCreationNanoseconds.load(ordering: .relaxed)
        return "\(threads) host threads, RSS \(rssKiB / 1024) MiB, \(fds) fds; VMs created \(vms.created), destroyed \(vms.destroyed); "
            + "vCPUs created off the kernel lock \(deferred) (avg \(deferred == 0 ? 0 : deferredNs / deferred / 1000) us); "
            + "TLB flush resumes \(VCPUPool.tlbFlushResumes.load(ordering: .relaxed)) "
            + "(\(VCPUPool.tlbFlushByVAResumes.load(ordering: .relaxed)) by VA)"
            + (VCPUPool.flushKeepsICache ? " (TLB only)" : " (TLB and I-cache)")
    }
}

nonisolated(unsafe) var abandonedLaunchers: [VMMLauncher] = []
nonisolated(unsafe) var threadReportSignalSource: DispatchSourceSignal?

let holdingTankKey = "XPC_SIMULATOR_HOLDING_TANK_HACK"

func runRootProcess(_ config: ExecConfiguration, quietSummary: Bool = false) -> Int32 {
    _ = TrapProfile.shared
    VCPUPool.guestCPUCount = GuestCPUs.count
    BootProfile.shared?.enable()
    if !MacOSMode.enabled, getenv("SWIFTCODE_CACHE_INDEX_PREWARM").map({ String(cString: $0) != "0" }) ?? true { config.cacheIndex.prewarm() }
    let system = DarwinSystem()
    let prewarmed = system.prewarmObjectPaths(fileSystem: config.makeRootFileSystem())
    if BootProfile.shared != nil { stderrLine("swiftcode-simd: object index: \(prewarmed) start-up objects noted") }
    if SchedPolicy.holdEnabled || SchedPolicy.qosEnabled {
        HostSched.threadID = { ckvmThreadID() }
        stderrLine("swiftcode-simd: sched: start hold \(SchedPolicy.holdEnabled ? "on" : "off"), thread QoS \(SchedPolicy.qosEnabled ? "on" : "off")"
            + (SchedPolicy.qosEnabled ? ", lock admission \(SchedPolicy.admissionEnabled ? "on" : "off"), host \(HostSched.configure())" : ""))
        system.holdLog = { stderrLine("swiftcode-simd: sched: " + $0) }
    }
    if config.trace || !config.options.tracePIDs.isEmpty || !config.options.traceNames.isEmpty {
        MachIPC.traceMessageStrings = true
    }
    let launcher = VMMLauncher(config: config)
    system.launcher = launcher
    config.camera?.install(on: system)
    system.processExited = { [weak launcher] pid, status in launcher?.processExited(pid: pid, status: status) }

    var bootstrapLogger: HostBootstrapLogger?
    var session: DeviceSession?
    var ioSurfaceService: IOSurfaceHostService?
    var metalService: MetalHostService?
    var hidService: HIDHostService?
    if config.device != nil || config.options.hostBootstrap {
        system.mach.hostBootstrapIsDefault = true
        let logPath = config.device?.hostBootstrapLogPath ?? config.runDir + "/swiftcode-host-bootstrap.log"
        let logger = HostBootstrapLogger(host: system.hostTask, logPath: logPath,
                                         discard: config.options.debugBootstrapDiscard)
        if config.device != nil {
            system.hostTask.pid = DarwinSystem.initPID
            system.hostTask.uid = DarwinFileSystem.guestUID
            system.hostTask.gid = DarwinFileSystem.guestGID
        }
        if let identity = config.options.debugHostIdentity {
            (system.hostTask.pid, system.hostTask.uid, system.hostTask.gid) = identity
        }
        if let device = config.device, !config.options.debugBootstrapDiscard {
            let s = DeviceSession(layout: device, host: system.hostTask, makeFileSystem: { config.makeRootFileSystem() })
            logger.onControlChannel = { [weak s] channel in s?.channelArrived(channel) }
            logger.beforeServicePortHandoff = { [weak s] port in s?.servicePortCreated(port) }
            if !config.options.debugNoHostServices {
                do {
                    let service = try IOSurfaceHostService(host: system.hostTask, log: { stderrLine("swiftcode-simd: " + $0) })
                    service.start()
                    s.hostServices.append((IOSurfaceHostService.serviceName, service.servicePort))
                    ioSurfaceService = service
                } catch {
                    stderrLine("swiftcode-simd: warning: cannot start the IOSurface service: \(error)")
                }
                hidService = startHIDService(config: config, session: s, host: system.hostTask)
                if !config.options.debugNoMetal {
                    var backendOptions = VulkanMetalBackend.Options()
                    backendOptions.log = { stderrLine("swiftcode-simd: metal backend: " + $0) }
                    backendOptions.importSlackWindow = SharedObjectArena.shared.map { (UInt(bitPattern: $0.base), UInt($0.size)) }
                    let translator: (any ShaderTranslator)? = config.options.metalTranslator.map {
                        let pool = AircTranslatorPool(executable: URL(fileURLWithPath: $0), count: backendOptions.translatorProcesses)
                        if ProcessInfo.processInfo.environment["SWIFTCODE_AIRC_PRESTART"] != "0" { pool.prestart() }
                        return pool
                    }
                    let names = MetalClientNames(system: system)
                    backendOptions.describeProcess = { names.describe($0) }
                    backendOptions.exemptFromRevocation = { names.isSystemUI($0) }
                    let backend = VulkanMetalBackend(translator: translator, options: backendOptions)
                    if backend.isAvailable {
                        if backend.options.earlyScheduled {
                            ioSurfaceService?.gpuWriteWait = { [weak backend] id in backend?.waitForSurfaceWrites(id) }
                        }
                        MetalCommandDecoder.anomalyLog = { stderrLine("swiftcode-simd: " + $0) }
                        do {
                            let metal = try MetalHostService(host: system.hostTask, backend: backend,
                                                             memory: HostMemoryEntryResolver(host: system.hostTask),
                                                             surfaces: ioSurfaceService.map { IOSurfacePortResolver(service: $0) },
                                                             log: { stderrLine("swiftcode-simd: " + $0) })
                            if ProcessInfo.processInfo.environment["SWIFTCODE_METAL_EVENT_CLOCK"] != "host" {
                                metal.setEventClock { [weak launcher] in
                                    guard let c = launcher?.snapshotSystemClock, c.frequency > 0 else {
                                        return ProcessInfo.processInfo.systemUptime
                                    }
                                    return Double(c.guestCounter) / Double(c.frequency)
                                }
                            }
                            names.service = metal
                            metal.start()
                            s.hostServices.append((MetalHostService.serviceNames[0], metal.servicePort))
                            metalService = metal
                            stderrLine("swiftcode-simd: Metal host service: \(MetalHostService.serviceNames[0]) on Vulkan")
                        } catch {
                            stderrLine("swiftcode-simd: warning: cannot start the Metal host service: \(error)")
                        }
                    } else {
                        stderrLine("swiftcode-simd: Metal host service: no Vulkan device; no Metal name offered")
                    }
                }
            }
            if !config.options.debugNoHostServices { config.camera?.start(host: system.hostTask, surfaces: ioSurfaceService, session: s) }
            session = s
        }
        do { try logger.start() } catch { die("cannot start the host bootstrap service: \(error)", status: 1) }
        bootstrapLogger = logger
    }

    if let snap = SnapshotSupport.shared {
        snap.stopHooks = (appPID: { [weak session] in session?.launchedAppPID },
                          appStepsRunning: { [weak session] in session?.appStepsRunning ?? false },
                          endSession: { [weak session] in session?.end() })
        snap.hostServiceState = { [weak session, weak metalService, weak hidService] in
            var out: [SnapshotFields] = []
            if let client = hidService?.snapshotClient {
                var g = SnapshotFields()
                g.string(ST_HostService.name, "hid")
                g.u64(ST_HostService.hidClient, UInt64(client))
                out.append(g)
            }
            if let st = session?.snapshotState {
                var g = SnapshotFields()
                g.string(ST_HostService.name, "device-session")
                g.u64(ST_HostService.channel, UInt64(st.channel))
                g.u64(ST_HostService.session, UInt64(st.session))
                out.append(g)
            }
            if let store = DefaultHostServices.scDynamicStore {
                var g = SnapshotFields()
                g.string(ST_HostService.name, "scdynamicstore")
                g.list(ST_HostService.sessions, store.snapshotSessions.map { s in
                    var e = SnapshotFields()
                    e.u64(1, UInt64(s.session))
                    e.u64s(2, s.notify.map(UInt64.init))
                    return e
                })
                out.append(g)
            }
            if let metal = metalService {
                var g = SnapshotFields()
                g.string(ST_HostService.name, "metal")
                g.u64s(ST_HostService.pids, metal.clientPIDs().map { UInt64(max(0, $0)) })
                out.append(g)
            }
            if let events = DefaultHostServices.fsEvents {
                var g = SnapshotFields()
                g.string(ST_HostService.name, "fsevents")
                g.list(ST_HostService.sessions, events.snapshotStreams.map(FSEventsSnapshot.fields))
                out.append(g)
            }
            return out
        }
        let saveGPU = getenv("SWIFTCODE_SNAPSHOT_GPU").map { String(cString: $0) != "0" } ?? true
        let hostTask = system.hostTask
        snap.quiescedServiceState = { [weak ioSurfaceService, weak metalService] in
            let inHand = hostTask.messagesInHandLocked
            if inHand > 0 { return .failure(SnapshotError("\(inHand) host-service messages in hand")) }
            var out: [SnapshotFields] = []
            if let audio = DefaultHostServices.audio {
                guard let st = audio.trySnapshotState() else { return .failure(SnapshotError("audio service busy")) }
                var g = SnapshotFields()
                g.string(ST_HostService.name, "audio")
                g.nested(ST_HostService.state, st)
                out.append(g)
            }
            guard saveGPU else { return .success(out) }
            if let reason = metalService?.snapshotBusyReason { return .failure(SnapshotError(reason)) }
            if let io = ioSurfaceService {
                guard let st = io.trySnapshotState() else { return .failure(SnapshotError("IOSurface service busy")) }
                var g = SnapshotFields()
                g.string(ST_HostService.name, "iosurface")
                g.nested(ST_HostService.state, st)
                out.append(g)
            }
            if let metal = metalService {
                guard let st = metal.trySnapshotState() else { return .failure(SnapshotError("Metal service busy")) }
                var g = SnapshotFields()
                g.string(ST_HostService.name, "metal-objects")
                g.nested(ST_HostService.state, st)
                out.append(g)
            }
            return .success(out)
        }
        let replayGPU = getenv("SWIFTCODE_RESTORE_GPU").map { String(cString: $0) != "0" } ?? true
        snap.restoreHostServices = { [weak session, weak ioSurfaceService, weak metalService, weak hidService] records in
            for r in records where r.string(ST_HostService.name) == "hid" {
                let client = r.u32(ST_HostService.hidClient)
                guard let hid = hidService, MachPortName.isValid(client) else { continue }
                hid.restoreRegistration(client: client)
            }
            if hidService != nil, !records.contains(where: { $0.string(ST_HostService.name) == "hid" }) {
                snapLog("restore: no HID registration in the snapshot; the device takes input only after its HID bundle registers")
            }
            if replayGPU {
                for r in records where r.string(ST_HostService.name) == "iosurface" {
                    guard let io = ioSurfaceService, let st = r.nested(ST_HostService.state) else { continue }
                    do {
                        let n = try io.restoreState(st)
                        snapLog("restore: IOSurface: \(n) surfaces")
                    } catch {
                        snapLog("restore: IOSurface state not restored: \(error)")
                    }
                }
                for r in records where r.string(ST_HostService.name) == "metal-objects" {
                    guard let metal = metalService, let st = r.nested(ST_HostService.state) else { continue }
                    let began = monotonicNanoseconds()
                    let rep = metal.restoreState(st)
                    snapLog("restore: Metal: \(rep.processes) processes, \(rep.objects) objects and \(rep.ghosts) kept recipes "
                        + "made again in \((monotonicNanoseconds() - began) / 1_000_000) ms (\(rep.failures) failed); contents: textures "
                        + "\(rep.textureBytes >> 10) KiB, buffers \(rep.bufferBytes >> 10) KiB, \(rep.contentsSkipped) skipped; "
                        + "\(rep.addressesChanged) buffer GPU addresses and \(rep.samplerIDsChanged) sampler IDs changed; heap slots "
                        + "\(rep.slotsKept) kept, \(rep.textureIDsChanged) texture IDs changed; argument-encoder members "
                        + "\(rep.argumentMembers), \(rep.argumentMembersChanged) written again")
                    for line in rep.lines { snapLog("restore: " + line) }
                }
            }
            for r in records where r.string(ST_HostService.name) == "audio" {
                guard let audio = DefaultHostServices.audio, let st = r.nested(ST_HostService.state) else { continue }
                do {
                    let n = try audio.restoreState(st)
                    snapLog("restore: audio: \(n) running IO contexts (resumed once the guest clock is set)")
                } catch {
                    snapLog("restore: audio state not restored: \(error)")
                }
            }
            for r in records where r.string(ST_HostService.name) == "scdynamicstore" {
                let list = r.list(ST_HostService.sessions).map { e in (session: e.u32(1), notify: e.u64s(2).map { UInt32(truncatingIfNeeded: $0) }) }
                DefaultHostServices.scDynamicStore?.restoreSessions(list)
                snapLog("restore: SCDynamicStore: \(list.count) sessions")
            }
            for r in records where r.string(ST_HostService.name) == "fsevents" {
                let list = r.list(ST_HostService.sessions).map(FSEventsSnapshot.record)
                DefaultHostServices.fsEvents?.restoreStreams(list)
                snapLog("restore: file events: \(list.count) streams")
            }
            for r in records where r.string(ST_HostService.name) == "device-session" {
                session?.reattach(channel: r.u32(ST_HostService.channel), session: r.u32(ST_HostService.session))
            }
        }
    }

    FrameProfile.shared?.prepareBoot(launcher: launcher, statePath: config.device?.framebufferStatePath, surfaces: ioSurfaceService)
    HomeWatch.atHome = { [weak system] in
        guard let system else { return "" }
        let (held, count) = system.lock.withLock { (system.lock.totalHeldNanoseconds, system.lock.acquisitions) }
        return "kernel lock held \(held / 1_000_000) ms (\(count) acquisitions)"
            + (SchedPolicy.holdEnabled || SchedPolicy.qosEnabled ? "; sched: " + system.schedReport + "; " + HostSched.report : "")
    }
    HomeWatch.startIfRequested(statePath: config.device?.framebufferStatePath, surfaces: ioSurfaceService)
    if let device = config.device, device.runtimePlatform() == .visionOS, let surfaces = ioSurfaceService {
        system.shellReadyHoldLabels = VisionHomeGuardPolicy.shellReadyHoldLabels()
        let policy = device.launchBundleID == nil && hidService != nil ? VisionHomeGuardPolicy.fromEnvironment() : nil
        VisionHomeGuard.start(policy: policy, statePath: device.framebufferStatePath, surfaces: surfaces, hid: hidService, system: system)
    }
    let rootKernel: DarwinKernel
    do {
        if let restored = try SnapshotSupport.shared?.restoreIfRequested(system: system, launcher: launcher, config: config) {
            rootKernel = restored
        } else {
            rootKernel = try system.spawnInitialProcess(config.rootRequest, fileSystem: config.makeRootFileSystem(),
                                                        exitedChildEnvironmentKey: config.device != nil ? holdingTankKey : nil)
        }
    } catch {
        let detail = launcher.lastLaunchFailure ?? "\(config.execPath): \(error)"
        die("cannot start the root process: \(detail)", status: (error as? DarwinErrnoError) != nil ? 66 : 1)
    }
    _ = rootKernel
    let started = monotonicMilliseconds()
    SnapshotSupport.shared?.rootStarted(system: system, launcher: launcher, config: config)
    let threadReport: @Sendable (String) -> Void = { [weak system] title in
        guard let system else { return }
        stderrLine("swiftcode-simd: thread report \(title):")
        for p in system.allProcesses {
            guard let k = p.kernel else { continue }
            let lines = k.lock.withLock { k.blockedThreadReport() }
            if lines.isEmpty { continue }
            stderrLine("swiftcode-simd: threads of pid \(p.pid) (\((p.executablePath as NSString).lastPathComponent)):")
            for line in lines { stderrLine("  " + line) }
        }
    }
    if let spec = getenv("SWIFTCODE_THREAD_REPORT_AT_S").map({ String(cString: $0) }) {
        let times = spec.split(separator: ",").compactMap { UInt64($0) }.sorted()
        Thread.detachNewThread {
            let start = monotonicMilliseconds()
            for t in times {
                while monotonicMilliseconds() - start < t * 1000 { usleep(200_000) }
                threadReport("at \(t) s")
            }
        }
    }
    signal(SIGUSR1, SIG_IGN)
    threadReportSignalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .global())
    threadReportSignalSource?.setEventHandler {
        threadReport("on SIGUSR1, \((monotonicMilliseconds() - started) / 1000) s after the root started")
    }
    threadReportSignalSource?.resume()
    TrapProfile.shared?.extraReport = { [weak system] in
        let split = system?.lock.splitReport ?? ""
        return (ImageBuildProfile.shared?.report ?? "") + (split.isEmpty ? "" : "\n" + split)
    }
    if TrapProfile.shared != nil {
        TrapProfile.threadUsage = {
            let u = hostThreadUsage()
            return .init(faults: u.faults, voluntarySwitches: u.voluntarySwitches, involuntarySwitches: u.involuntarySwitches)
        }
        TrapProfile.currentThreadID = { ckvmThreadID() }
        let sampleUS = getenv("SWIFTCODE_TRAP_PROFILE_SAMPLE_US").flatMap { UInt32(String(cString: $0)) } ?? 2000
        if sampleUS > 0 { TrapProfile.shared?.startHolderSampler(lock: system.lock, every: sampleUS) }
        #if os(Linux) && arch(arm64)
        if let path = getenv("SWIFTCODE_TRAP_PROFILE").map({ String(cString: $0) }) {
            LockStackSampler.startIfRequested(lock: system.lock, profilePath: path, portLock: system.mach.portLock)
        }
        #endif
    }
    TrapProfile.shared?.startPeriodicDump()
    BootProfile.shared?.launcherForReport = launcher
    BootProfile.shared?.startSampler(launcher: launcher, lock: system.lock)
    BootProfile.shared?.startPCSampler(launcher: launcher)
    if let gauge = GaugeRecorder.shared {
        gauge.launchedPID = { [weak session] in session?.launchedAppPID }
        gauge.start(launcher: launcher)
    }
    if let debug = config.options.debugServer {
        let server = SimDebugServer(options: debug)
        server.launchedPID = { [weak session] in session?.launchedAppPID }
        switch config.device?.deviceType.platform {
        case .watchOS?: server.osType = "watchos"
        case .visionOS?: server.osType = "xros"
        default: server.osType = "ios"
        }
        if let o = getenv("SWIFTCODE_DEBUG_OSTYPE").map({ String(cString: $0) }), !o.isEmpty { server.osType = o }
        (server.osVersion, server.osBuild) = SimDebugServer.runtimeVersion(root: config.root)
        server.launchExecutable = config.options.installApp.flatMap { app -> String? in
            let plist = absolutePath(app) + "/Info.plist"
            guard let data = FileManager.default.contents(atPath: plist),
                  let p = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
            return p["CFBundleExecutable"] as? String
        }
        SimDebugServer.shared = server
        server.start(launcher: launcher)
    }
    if config.options.debugThreadReport {
        DarwinKernel.recordKnoteHistory = true
        system.lock.slowHoldNanoseconds = 20_000_000
        system.lock.profileHolds = true
        system.lock.slowHoldReporter = { context, ns in
            let what = context.map { c in
                "pid \(c.kernel?.pid ?? -1) thread \(c.threadID) trap \(c.trapInProgress.map { String(Int64(bitPattern: $0.x16)) } ?? "?")"
            } ?? "a service thread"
            stderrLine("swiftcode-simd: monitor: kernel lock held \(ns / 1_000_000) ms by \(what)")
        }
        let monitor = Thread { [weak launcher] in
            var lastHeld: UInt64 = 0, lastCount: UInt64 = 0, lastTime = monotonicMilliseconds()
            while let l = launcher {
                Thread.sleep(forTimeInterval: 20)
                let (held, count) = system.lock.withLock { (system.lock.totalHeldNanoseconds, system.lock.acquisitions) }
                let now = monotonicMilliseconds()
                stderrLine("swiftcode-simd: monitor: kernel lock busy \((held - lastHeld) / 10_000 / max(now - lastTime, 1))% "
                    + "over \(now - lastTime) ms, \(count - lastCount) acquisitions")
                (lastHeld, lastCount, lastTime) = (held, count, now)
                let profile = system.lock.withLock { system.lock.holdProfile }
                let top = profile.sorted { $0.value.ns > $1.value.ns }.prefix(12).map {
                    "\($0.key == Int64.min ? "service" : String($0.key)): \($0.value.ns / 1_000_000) ms/\($0.value.count)"
                }
                stderrLine("swiftcode-simd: monitor: lock hold by trap (cumulative): " + top.joined(separator: ", "))
                for line in l.longHandlerReport(ms: 20_000) { stderrLine("swiftcode-simd: monitor: " + line) }
                for line in l.longGuestRunReport(ms: 5_000) { stderrLine("swiftcode-simd: monitor: " + line) }
                for line in l.rootWorkerStates() { stderrLine("swiftcode-simd: monitor: root " + line) }
            }
        }
        monitor.start()
    }

    var extraKernels: [DarwinKernel] = []
    for i in 0..<config.options.debugExtraImages {
        let path = config.options.debugExtraExec.map(absolutePath) ?? config.execPath
        let kernel = DarwinKernel(fileSystem: config.makeRootFileSystem(), pid: Int32(900 + i))
        let request = ProcessImageRequest(executablePath: path, hostExecutablePath: path,
                                          argv: [path] + config.options.debugExtraArguments,
                                          envp: SimulatorEnvironment.make(runtimeRoot: config.root))
        do {
            try kernel.lock.withLock { _ = try launcher.launch(request, kernel: kernel) }
            extraKernels.append(kernel)
        } catch {
            stderrLine("swiftcode-simd: debug extra image \(i): \(error)")
        }
    }

    var fold: FoldController?
    if let device = config.device, let second = device.deviceType.secondDisplay, let hid = hidService {
        fold = FoldController(hid: hid, second: second, statePath: device.memoryFile("fold.state").host,
                              restoring: device.restoring, log: { stderrLine("swiftcode-simd: " + $0) })
        fold?.innerPublished = device.deviceType.publishedSecondDisplay != nil
    }
    nonisolated(unsafe) let panelCapture: (String, String) -> String = { [weak ioSurfaceService, weak fold] name, path in
        guard let device = config.device, let service = ioSurfaceService else { return "no display service" }
        let panels = device.deviceType.panels
        let records = panels.map { FrameRecordReader(path: device.framebufferStatePath, slot: $0.slot).read() }
        let panel: PanelInfo
        if name == "active" {
            panel = activePanel(panels, model: fold?.state, records: records, black: records.map { service.presentedFrameIsBlack($0) })
        } else if let p = panels.first(where: { $0.name == name }) {
            panel = p
        } else {
            return "no display \(name) (this device has \(panels.map(\.name).joined(separator: ", ")))"
        }
        let c = ScreenCapture(statePath: device.framebufferStatePath, service: service, slot: panel.slot,
                              rotation: PanelPicture.uprightRotation(mountRotation: panel.mountRotation), displayName: panel.name)
        return c.capture(to: path)
    }
    var vision: VisionInputController?
    if let device = config.device, device.deviceType.family == .vision, let hid = hidService {
        let vhmd = VisionHMDClient(host: system.hostTask, find: { [weak session] in
            guard let c = session?.boundControl else {
                throw LaunchSimControlError(operation: "find \(VisionHMDClient.serviceName): no session", code: 3)
            }
            return try c.findEndpoint(VisionHMDClient.serviceName)
        }, log: { stderrLine("swiftcode-simd: " + $0) })
        let screen = device.deviceType.screen
        vision = VisionInputController(hid: hid, vhmd: vhmd, pointWidth: screen.pointWidth, pointHeight: screen.pointHeight,
                                       log: { stderrLine("swiftcode-simd: " + $0) })
        if let room = config.options.visionRoom, device.restoring, let vision {
            Thread.detachNewThread {
                for attempt in 1...12 {
                    Thread.sleep(forTimeInterval: 5)
                    let answer = vision.handle(["vision", "room", room]) ?? ""
                    stderrLine("swiftcode-simd: visionOS: --room after the restore (attempt \(attempt)): \(answer)")
                    if answer.hasPrefix("ok") { return }
                }
            }
        }
    }
    var control: DeviceControlServer?
    var pairingHost: PairingHost?
    if let device = config.device {
        let server = DeviceControlServer(path: DeviceLayout.controlSocketPath(dev: device.dev), fold: fold,
                                         summary: { [weak fold, weak ioSurfaceService] in
                                             guard let fold else { return "\(device.deviceType.name): does not fold" }
                                             let panels = device.deviceType.panels
                                             let records = panels.map { FrameRecordReader(path: device.framebufferStatePath, slot: $0.slot).read() }
                                             let black = records.map { ioSurfaceService?.presentedFrameIsBlack($0) }
                                             let shown = activePanel(panels, model: fold.state, records: records, black: black)
                                             return fold.state.summary + "; showing \(shown.name)"
                                                 + (fold.sweepTarget.map { "; sweeping to \($0)°" } ?? "")
                                                 + "; backlight " + zip(panels, records).map { "\($0.name) \($1?.backlight.map(String.init) ?? "-")" }.joined(separator: ", ")
                                                 + "; frames " + zip(panels, black).map { "\($0.name) \($1.map { $0 ? "black" : "lit" } ?? "-")" }.joined(separator: ", ")
                                         },
                                         capture: panelCapture)
        let files = DeviceSettingsFiles(dev: device.dev, guestData: device.guestData)
        let settings = SimSettingsController(files: files, runtimeRoot: config.root, log: { stderrLine("swiftcode-simd: " + $0) })
        settings.onAudio = { s in DefaultHostServices.audio?.setOutput(volume: Float(s.volume) / 100, muted: s.output == .none) }
        settings.onAudio?(files.audio())
        HostStreamSockets.serve(paths: SettingsChannel.guestPaths, with: settings)
        if device.settingsAgent != nil {
            stderrLine("swiftcode-simd: settings: agent \(device.settingsAgentHostPath) (log \(device.settingsAgentLogPath))")
        }
        try? Data((device.udid + "\n").utf8).write(to: URL(fileURLWithPath: device.dev + "/" + PairingDeviceDirectory.udidRecordName),
                                                   options: .atomic)
        let pairing = PairingHost(udid: device.udid, dev: device.dev, set: PairingHost.deviceSet(for: device.dev),
                                  family: PairingDeviceDirectory.family(typeID: device.deviceType.id), host: system.hostTask,
                                  session: session, log: { stderrLine("swiftcode-simd: " + $0) })
        HostStreamSockets.serve(paths: PairingAgentChannel.guestPaths, with: pairing)
        pairing.start()
        pairingHost = pairing
        if device.pairingAgent != nil {
            stderrLine("swiftcode-simd: pairing: agent \(device.pairingAgentHostPath) (log \(device.pairingAgentLogPath))")
        }
        let health = HealthHost(dev: device.dev, isWatch: device.deviceType.family == .watch, log: { stderrLine("swiftcode-simd: " + $0) })
        HostStreamSockets.serve(paths: HealthChannel.guestPaths, with: health)
        if device.healthAgent != nil, FileManager.default.fileExists(atPath: device.healthAgentPlistPath) {
            stderrLine("swiftcode-simd: health: agent \(device.healthAgentHostPath) (log \(device.healthAgentLogPath))")
        }
        let buttonFamily = WatchInputCommand.buttonFamily(device.deviceType)
        server.moreCommands = { [weak hidService, weak vision] words in
            if let answer = pairing.controlCommand(words) { return answer }
            if words.first == VisionInputController.verb {
                return vision?.handle(words) ?? "error: vision: this device is not a Vision Pro (or has no HID bundle)"
            }
            if words.first == "health" { return health.handle(words) }
            if let answer = WatchInputCommand.handle(words, hid: hidService, family: buttonFamily) { return answer }
            guard let verb = words.first, SimSettingsCommand.verbs.contains(verb) else { return nil }
            return settings.handle(words)
        }
        if server.start() { control = server } else { stderrLine("swiftcode-simd: warning: no control socket at \(server.path)") }
    }

    let screenshotDisplay = config.options.screenshotDisplay ?? "active"
    if config.device != nil, ioSurfaceService != nil, let path = config.options.screenshotPath {
        for seconds in config.options.screenshotTimes.sorted() {
            let at = (path as NSString).deletingPathExtension + "-\(seconds)s.png"
            Thread.detachNewThread {
                Thread.sleep(until: Date(timeIntervalSinceNow: 0).addingTimeInterval(
                    max(0, Double(seconds) - Double(monotonicMilliseconds() - started) / 1000)))
                stderrLine("swiftcode-simd: screenshot at \(seconds) s: " + panelCapture(screenshotDisplay, at))
            }
        }
    }
    if let device = config.device, SnapshotSupport.shared?.settings.restoreDirectory != nil {
        let statePath = device.framebufferStatePath
        let slots = device.deviceType.panels.map(\.slot)
        Thread.detachNewThread {
            let readers = slots.map { FrameRecordReader(path: statePath, slot: $0) }
            let first = readers.map { $0.read() }
            for _ in 0..<1200 {
                usleep(250_000)
                for (i, reader) in readers.enumerated() {
                    guard let now = reader.read(), now != first[i] else { continue }
                    stderrLine("swiftcode-simd: snapshot: restore: first new frame (frame \(first[i].map { String($0.frame) } ?? "none") -> "
                        + "\(now.frame)\(slots.count > 1 ? " on display slot \(slots[i])" : "")) \(monotonicMilliseconds() - started) ms after the root started")
                    return
                }
            }
            stderrLine("swiftcode-simd: snapshot: restore: no new frame in 300 s (frame \(first.first.flatMap { $0.map { String($0.frame) } } ?? "none"))")
        }
    }

    FrameProfile.shared?.start(launcher: launcher, statePath: config.device?.framebufferStatePath)

    let guestClock: () -> UInt64? = { [weak launcher] in
        guard let c = launcher?.snapshotSystemClock else { return nil }
        let scale = GuestTimebase.ClockScale(from: c.frequency, to: GuestTimebase.frequency(hostFrequency: c.frequency))
        return scale.apply(c.guestCounter)
    }
    let display = startDisplayServer(config: config, surfaces: ioSurfaceService, session: session, hid: hidService, fold: fold,
                                     vision: vision, started: started, guestClock: guestClock)
    display?.commands = { [weak control] line in control?.handle(line) ?? "error: no control commands for this device" }
    DefaultHostServices.audio?.setGuestClock { [weak launcher] in
        guard let c = launcher?.snapshotSystemClock else { return (MachTimebase.now(), MachTimebase.frequency) }
        let hz = GuestTimebase.frequency(hostFrequency: c.frequency)
        return (GuestTimebase.ClockScale(from: c.frequency, to: hz).apply(c.guestCounter), hz)
    }

    config.camera?.setGuestClock { [weak launcher] in
        guard let c = launcher?.snapshotSystemClock else { return (MachTimebase.now(), MachTimebase.frequency) }
        let hz = GuestTimebase.frequency(hostFrequency: c.frequency)
        return (GuestTimebase.ClockScale(from: c.frequency, to: hz).apply(c.guestCounter), hz)
    }
    if let camera = config.camera, camera.optIn.isOn {
        deviceCameraControl = { [weak session] words in camera.handle(words, session: session) }
    }
    var result = launcher.superviseRoot(timeoutMilliseconds: config.timeout)
    pairingHost?.stop()
    config.camera?.stop()
    DefaultHostServices.audio?.finishCapture()
    display?.stop(message: "the device run ended")
    if config.device != nil, ioSurfaceService != nil, let path = config.options.screenshotPath {
        stderrLine("swiftcode-simd: screenshot: " + panelCapture(screenshotDisplay, path))
    }
    control?.stop()
    config.device?.finishMemoryDirectory()
    if config.options.debugExtraWait, !result.watchdog {
        let left = launcher.superviseAll(deadline: started + config.timeout)
        if left > 0 { result = (71, "watchdog: \(left) images still running after \(config.timeout) ms", true) }
    }
    var watchdogReport: String?
    if result.watchdog, config.device != nil, launcher.waitStatus(of: rootPID) == nil {
        result = (0, "device run ended after \(config.timeout) ms (--timeout-ms); launchd_sim (pid \(rootPID)) was still running", false)
        _ = SnapshotSupport.shared?.stopAndSave(reason: "the run's time limit (--timeout-ms)")
        if let session, session.isBound, !config.options.debugNoSessionEnd {
            session.end()
            let shutdown = launcher.superviseRoot(timeoutMilliseconds: 15_000)
            if shutdown.watchdog {
                result.message += "; the session was ended, but launchd_sim did not exit within 15 s"
                if config.trace || config.options.debugThreadReport { watchdogReport = launcher.watchdogReport() }
            } else {
                result = (shutdown.status,
                          "device run ended after \(config.timeout) ms (--timeout-ms); session ended, launchd_sim (pid \(rootPID)) "
                            + "shut down: \(shutdown.message)", false)
            }
        } else if config.trace || config.options.debugThreadReport {
            watchdogReport = launcher.watchdogReport()
        }
    } else if result.watchdog {
        watchdogReport = launcher.watchdogReport()
    }
    if !quietSummary || result.status != 0 { stderrLine("swiftcode-simd: \(result.message)") }
    if let watchdogReport { stderrLine(watchdogReport) }
    if config.options.debugThreadReport {
        for p in system.allProcesses {
            guard let k = p.kernel else { continue }
            let lines = k.lock.withLock { k.blockedThreadReport() }
            if lines.isEmpty { continue }
            stderrLine("swiftcode-simd: blocked threads of pid \(p.pid) (\((p.executablePath as NSString).lastPathComponent)):")
            for line in lines { stderrLine("  " + line) }
        }
    }

    var stillAlive = launcher.liveCount
    if !result.watchdog {
        if stillAlive > 0 { system.terminateAllProcesses() }
        stillAlive = launcher.stopAll(milliseconds: 1000)
    }
    TrapProfile.shared?.dump()
    BootProfile.shared?.writeReport(records: launcher.records)
    GaugeRecorder.shared?.finish(reason: "the run ended")
    SimDebugServer.shared?.stop()

    let records = launcher.records
    let locked = !result.watchdog
    if let first = records.first {
        let line = first.finalSummary ?? first.image?.summary(locked: locked) ?? "no summary"
        if !quietSummary { stderrLine("swiftcode-simd: \(line)") }
        if config.trace, locked, let unimplemented = first.image?.unimplementedSummary() {
            stderrLine("swiftcode-simd: unimplemented: " + unimplemented)
        }
    }
    if records.count > 1 && !quietSummary {
        stderrLine("swiftcode-simd: processes (\(records.count) images):")
        for record in records {
            var line = "  pid \(record.pid) [image \(record.serial)] \((record.executable as NSString).lastPathComponent): \(record.endDescription)"
            if let w = launcher.waitStatus(of: record.pid) { line += "; process \(VMMLauncher.describe(waitStatus: w))" }
            if !record.tornDown { line += "; still running at host exit" }
            if let summary = record.finalSummary ?? record.image?.summary(locked: false) {
                line += "; " + summary.split(separator: ";").first.map(String.init)!
            }
            if let missing = record.finalUnimplemented { line += "; unimplemented: " + missing }
            stderrLine(line)
        }
    }
    if records.count > 1 && !quietSummary {
        let table = system.allProcesses
        if !table.isEmpty {
            stderrLine("swiftcode-simd: process table at host exit: " + table.map { "\($0)" }.joined(separator: "; "))
        }
    }
    if !quietSummary, SchedPolicy.holdEnabled || SchedPolicy.qosEnabled {
        stderrLine("swiftcode-simd: sched: " + system.schedReport + "; " + HostSched.report)
    }
    if !quietSummary {
        stderrLine("swiftcode-simd: host: \(HostStats.current())" + (stillAlive > 0 ? "; \(stillAlive) images not torn down" : ""))
    }
    if let metalService {
        let t0 = monotonicMilliseconds()
        let drained = metalService.shutdown()
        if !quietSummary {
            stderrLine("swiftcode-simd: Metal host service: shut down in \(monotonicMilliseconds() - t0) ms"
                + (drained ? "" : " (a connection was still busy)"))
        }
    }
    ioSurfaceService?.stop()
    if let bootstrapLogger {
        bootstrapLogger.stop()
        if stillAlive == 0 { system.hostTask.shutdown() }
    }
    if let session, !quietSummary {
        for line in session.resultLines { stderrLine("swiftcode-simd: one-shot " + line) }
    }
    if let device = config.device, device.launchBundleID != nil, !quietSummary {
        for path in [device.appStdoutHostPath, device.appStderrHostPath] {
            guard let data = FileManager.default.contents(atPath: path) else {
                stderrLine("swiftcode-simd: app output: no file \(path)")
                continue
            }
            stderrLine("swiftcode-simd: app output (\(path), \(data.count) bytes)" + (data.isEmpty ? "" : ":\n" + String(decoding: data, as: UTF8.self)))
        }
    }
    if let device = config.device, !quietSummary {
        let log = device.tmpHostPath + "/launchd.log"
        let size = try? FileManager.default.attributesOfItem(atPath: log)[.size] as? Int
        stderrLine("swiftcode-simd: TMP/launchd.log (\(log)): " + (size.map { "\($0) bytes" } ?? "absent"))
        for index in device.oneshots.indices {
            for err in [false, true] {
                let path = device.oneshotOutputHostPath(index, err: err)
                guard let data = FileManager.default.contents(atPath: path) else {
                    stderrLine("swiftcode-simd: \(device.oneshotLabel(index)) \(err ? "stderr" : "stdout"): no file \(path)")
                    continue
                }
                stderrLine("swiftcode-simd: \(device.oneshotLabel(index)) \(err ? "stderr" : "stdout") (\(path), \(data.count) bytes)"
                    + (data.isEmpty ? "" : ":\n" + String(decoding: data, as: UTF8.self)))
            }
        }
    }
    if stillAlive > 0 { abandonedLaunchers.append(launcher) }
    extraKernels.removeAll()
    return result.status
}

func removeRunDirectory(_ config: ExecConfiguration) {
    guard let path = config.runDirToRemove else { return }
    do {
        try FileManager.default.removeItem(atPath: path)
    } catch {
        stderrLine("swiftcode-simd: warning: cannot remove the run directory \(path): \(error)")
    }
}

func runExec(_ options: Options) throws -> Never {
    CPUFeatureSetup.install()
    let config = try ExecConfiguration(options)
    let count = options.repeatCount
    guard count > 1 else {
        let status = runRootProcess(config)
        removeRunDirectory(config)
        exit(status)
    }

    var firstFailure: Int32?
    var afterFirst = HostStats()
    let before = HostStats.current()
    stderrLine("swiftcode-simd: repeat: before the first run: \(before)")
    for run in 1...count {
        config.quietRuns = run > 1 && !config.trace
        let status = runRootProcess(config, quietSummary: config.quietRuns)
        if status != 0 && firstFailure == nil { firstFailure = status }
        let stats = HostStats.current()
        if run == 1 { afterFirst = stats }
        if run == 1 || run == count || run % 10 == 0 || status != 0 {
            stderrLine("swiftcode-simd: repeat \(run)/\(count): status \(status); \(stats)")
        }
    }
    let after = HostStats.current()
    let vms = VMCounters.shared.snapshot
    stderrLine("swiftcode-simd: repeat summary: \(count) runs, \(firstFailure == nil ? "all exited 0" : "first failure status \(firstFailure!)"); "
        + "after run 1 -> after run \(count): host threads \(afterFirst.threads) -> \(after.threads), "
        + "RSS \(afterFirst.rssKiB / 1024) -> \(after.rssKiB / 1024) MiB, fds \(afterFirst.fds) -> \(after.fds); "
        + "VMs live \(vms.created - vms.destroyed)")
    let leakFree = after.threads == afterFirst.threads && after.fds == afterFirst.fds && vms.created == vms.destroyed
        && after.rssKiB - afterFirst.rssKiB <= 8 * 1024
    stderrLine("swiftcode-simd: repeat leak check: \(leakFree ? "ok" : "FAILED") "
        + "(threads, fds and VMs flat; RSS growth \((after.rssKiB - afterFirst.rssKiB) / 1024) MiB of 8 allowed)")
    removeRunDirectory(config)
    exit(firstFailure ?? 0)
}
#endif
