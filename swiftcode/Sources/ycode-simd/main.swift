import YcodeDarwinABI
import YcodeHypervisor

runCameraCommandIfRequested(CommandLine.arguments)

#if os(Linux) && arch(arm64)
import CKVM
import Foundation
import Glibc
import YcodeDarwinKernel
import YcodeMachO
import YcodeRelease
import YcodeDisplayStream

let usage = """
    usage: swiftcode-simd --exec <macho> --runtime-root <dir> [--run-dir <dir> | --keep-run-dir] [--trace]
                      [--timeout-ms N] [--max-exits N] [--shim <shim.bin>] [--host-stubs <host_stubs.bin>]
                      [--host-libs <dir>] [--keep-going] [--libfunc-return <name>=<value>[,...]] [--repeat N]
                      [--env K=V]... [--host-bootstrap [--debug-bootstrap-discard]] [--exec-args <arg>...]
           swiftcode-simd --device <dir> --runtime-root <dir> [--udid <UDID>] [--job-path <dir>]... [--env K=V]...
                      [--device-type <id>] [--vision-display <w>x<h>] (--list-device-types; default: iphone-duo on iOS 27.1, iphone-18-pro on iOS 27.0
                      runtimes, vision-pro on visionOS, apple-watch-series-12-46mm on watchOS; a device keeps its first type)
                      [--runtime-paths] [--oneshot "/guest/program arg..."]... [--oneshot-delay S] [--runtime-job <label>]...
                      [--install-app <host .app>] [--launch <bundle id> [--app-arg A]... [--app-env K=V]... [--app-url U]]
                      [--guest-tools <dir with ylaunch>] [--framebuffer-library <SimFramebuffer binary> | none]
                      [--settings-agent <swiftcode-settings-agent> | none] [--environment-overrides] (simulator-features.md)
                      [--profile <out.gaugetrace> [--profile-rate HZ] [--profile-hang-ms MS] [--profile-seconds S]
                       [--profile-process NAME]... [--profile-no-signposts]] (Gauge, the profiler: specs/ide/profiler.md §3.1)
                      [--debug-server unix:<path>|[<host>:]<port> [--debug-server-log] [--debug-launch-stopped]] (LLDB's
                       gdb-remote protocol for one guest process; a connection attaches to the --launch app, which
                       --debug-launch-stopped holds at its first instruction until then: specs/simulator/debug-stub.md)
                      [--pairing-agent <swiftcode-pairing-agent> | none] (device-pairing.md §8; the device set holding the
                      pair records: $SWIFTCODE_DEVICE_SET, else the directory holding DEV)
                      [--health-agent <SwiftCodeHealth.app> | none] (health-simulation.md "SwiftCode implementation"; the
                      guest health agent, run on iOS and watchOS devices)
                      [--screenshot <path.png> [--screenshot-at S]... [--display LCD|LCD-1|active]] [--skip-first-boot-migration]
                      [--camera on|off|synthetic|/dev/videoN|v4l2:<id> [--camera-position back|front|external]]
                      [--camera-library <libSwiftCodeCamera.dylib>] (the device's camera, kept for later boots; default off;
                      camera.md "SwiftCode implementation")
                      [--display-server unix:<path> | [<host>:]<port>] (live display and input; display-stream.md)
                      [--hid-bundle <SimHID.framework dir> | none] (default with --display-server: the built one)
                      [--room <key>] (visionOS: the room for this boot, e.g. MuseumDay; visionos.md §5.5.4)
                      [--metal-translator <swiftcode-airc>] (default: $SWIFTCODE_AIRC, next to swiftcode-simd, $PATH)
                      [--gpu-cache-dir <dir> | --no-gpu-cache] (Vulkan pipeline cache and swiftcode-airc
                      translation cache; default for --device: ${XDG_CACHE_HOME:-~/.cache}/swiftcode/gpu)
                      [--debug-plist-bool KEY=true|false]... [--debug-no-session-end]
                      [--trace] [--keep-going] [--timeout-ms N] [--host-libs <dir>] [--debug-bootstrap-discard]
                      [--exec-args <arg>...]
                      [--debug-extra-images N [--debug-extra-exec <macho>] [--debug-extra-arg A]... [--debug-extra-wait]]
           swiftcode-simd --macos <macOS arm64 program> [--macos-root <dir>] [--env K=V]... [--trace] [--timeout-ms N]
                      [--run-dir <dir> | --keep-run-dir] [--exec-args <arg>...]   (specs/macos/macos-apps.md;
                      the root defaults to MacUserland/out/root, built by sh MacUserland/build.sh)
           swiftcode-simd --list-device-types   (the --device-type IDs, one per line, the default first)
           swiftcode-simd --device <dir> --control <command...> | --fold closed|half|open|<degrees> [--instant]
                      | --ui appearance|content_size|increase_contrast|liquid-glass|color-filter … | --accessibility <switch> [on|off]
                      | --location set|preset|start|run|file|clear|list … | --audio volume|output|input|devices …
                      | --overrides <bundle id> … | --settings   (SimSettings.swift; a stopped device: written for its next boot)
                      | --orientation <name> | --rotate left|right | --fold-state   (a running device; FoldControl.swift)
                      | --health status|import|scenario|stream|stop|clear|grant|revoke|seed …   (HealthHost.swift,
                      HealthClient.swift; health-simulation.md "SwiftCode implementation")
           swiftcode-simd --device <dir> --privacy grant|revoke|reset camera|microphone <bundle id>   (CameraDevice.swift)
           swiftcode-simd [--device-set <dir>] --pair <watch> <phone> | --unpair <pair> | --pair-activate <pair>
                      | --list-pairs [--json]   (PairingCommand.swift; device-pairing.md §2.2, §8)
           swiftcode-simd --shim <shim.bin> --el0 <el0.bin> [--trace] [--timeout-ms N] [--max-exits N]
                      [--vcpus N [--rounds R]]
           swiftcode-simd --kvm-smoke
           swiftcode-simd --camera-list
           swiftcode-simd --camera-probe [--camera auto|synthetic|/dev/videoN|<id>] [--frames N] [--size WxH] [--fps F]
                      [--pixel-format 420v|420f|BGRA] [--source-format YUYV|MJPG|NV12] [--out <frame.png>] [--scale K]
    """

struct Options {
    var shimPath: String?
    var el0Path: String?
    var execPath: String?
    var macOSPath: String?
    var macOSRoot: String?
    var runtimeRoot: String?
    var runDir: String?
    var keepRunDir = false
    var hostStubsPath: String?
    var hostLibsPath: String?
    var trace = false
    var keepGoing = false
    var libfuncReturns: [String: UInt64] = [:]
    var kvmSmoke = false
    var vcpus: Int?
    var rounds = 2
    var timeoutMilliseconds: UInt64?
    var maxExits: Int?
    var devicePath: String?
    var deviceType: DeviceType?
    var udid: String?
    var jobPaths: [String] = []
    var oneshots: [[String]] = []
    var runtimeJobs: [String] = []
    var runtimePaths = false
    var oneshotDelay: Int?
    var debugNoSessionEnd = false
    var screenshotPath: String?
    var skipFirstBootMigration = false
    var screenshotTimes: [Int] = []
    var screenshotDisplay: String?
    var displayServer: DisplayAddress?
    var hidBundle: String?
    var visionRoom: String?
    var debugNoMetal = false
    var metalTranslator: String?
    var gpuCacheDirectory: String?
    var noGPUCache = false
    var debugNoHostServices = false
    var installApp: String?
    var launchBundleID: String?
    var appArguments: [String] = []
    var appURL: String?
    var appEnvironment: [String] = []
    var guestTools: String?
    var settingsAgent: String?
    var pairingAgent: String?
    var healthAgent: String?
    var environmentOverrides = false
    var profile: GaugeOptions?
    var debugServer: DebugServerOptions?
    var framebufferLibrary: String?
    var camera: String?
    var cameraPosition: String?
    var cameraLibrary: String?
    var debugHostIdentity: (pid: Int32, uid: UInt32, gid: UInt32)?
    var debugThreadReport = false
    var tracePIDs: Set<Int32> = []
    var traceNames: Set<String> = []
    var plistBoolOverrides: [String: Bool] = [:]
    var debugBootstrapDiscard = false
    var hostBootstrap = false
    var execArguments: [String] = []
    var environment: [String] = []
    var repeatCount = 1
    var debugExtraImages = 0
    var debugExtraExec: String?
    var debugExtraArguments: [String] = []
    var debugExtraWait = false
}

func writeFD(_ fd: Int32, _ text: String) { writeFD(fd, Array(text.utf8)) }

func writeFD(_ fd: Int32, _ bytes: [UInt8]) {
    var offset = 0
    while offset < bytes.count {
        let n = bytes.withUnsafeBytes { Glibc.write(fd, $0.baseAddress! + offset, $0.count - offset) }
        if n < 0 {
            if errno == EINTR { continue }
            return
        }
        offset += n
    }
}

func stderrLine(_ text: String) { writeFD(2, text + "\n") }

func die(_ message: String, status: Int32) -> Never {
    stderrLine("swiftcode-simd: \(message)")
    exit(status)
}

func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

func splitCommandLine(_ line: String) -> [String] {
    var words: [String] = [], word = "", quote: Character?, inWord = false
    for c in line {
        if let q = quote {
            if c == q { quote = nil } else { word.append(c) }
        } else if c == "'" || c == "\"" {
            quote = c
            inWord = true
        } else if c == " " {
            if inWord { words.append(word) }
            word = ""
            inWord = false
        } else {
            word.append(c)
            inWord = true
        }
    }
    if inWord { words.append(word) }
    return words
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.dropFirst().makeIterator()
    func value(for flag: String) -> String {
        guard let value = iterator.next() else { die("\(flag) needs a value\n\(usage)", status: 64) }
        return value
    }
    while let argument = iterator.next() {
        switch argument {
        case "--shim": options.shimPath = value(for: argument)
        case "--el0": options.el0Path = value(for: argument)
        case "--exec": options.execPath = value(for: argument)
        case "--macos": options.macOSPath = value(for: argument)
        case "--macos-root": options.macOSRoot = value(for: argument)
        case "--runtime-root": options.runtimeRoot = value(for: argument)
        case "--run-dir": options.runDir = value(for: argument)
        case "--keep-run-dir": options.keepRunDir = true
        case "--host-stubs": options.hostStubsPath = value(for: argument)
        case "--host-libs": options.hostLibsPath = value(for: argument)
        case "--trace": options.trace = true
        case "--keep-going": options.keepGoing = true
        case "--libfunc-return":
            for item in value(for: argument).split(separator: ",") {
                let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { die("--libfunc-return needs name=value", status: 64) }
                let text = parts[1].hasPrefix("0x") ? String(parts[1].dropFirst(2)) : parts[1]
                guard let v = parts[1].hasPrefix("-") ? Int64(parts[1]).map({ UInt64(bitPattern: $0) })
                        : UInt64(text, radix: parts[1].hasPrefix("0x") ? 16 : 10) else {
                    die("--libfunc-return: bad value '\(parts[1])'", status: 64)
                }
                options.libfuncReturns[parts[0]] = v
            }
        case "--kvm-smoke": options.kvmSmoke = true
        case "--vcpus":
            guard let n = Int(value(for: argument)), n > 0, n <= VCPUSlots.lowCount else { die("--vcpus needs 1...\(VCPUSlots.lowCount)", status: 64) }
            options.vcpus = n
        case "--rounds":
            guard let n = Int(value(for: argument)), n > 0 else { die("--rounds needs a positive integer", status: 64) }
            options.rounds = n
        case "--timeout-ms":
            guard let n = UInt64(value(for: argument)), n > 0 else { die("--timeout-ms needs a positive integer", status: 64) }
            options.timeoutMilliseconds = n
        case "--repeat":
            guard let n = Int(value(for: argument)), n > 0 else { die("--repeat needs a positive integer", status: 64) }
            options.repeatCount = n
        case "--debug-extra-images":
            guard let n = Int(value(for: argument)), n >= 0, n <= 64 else { die("--debug-extra-images needs 0...64", status: 64) }
            options.debugExtraImages = n
        case "--debug-extra-exec": options.debugExtraExec = value(for: argument)
        case "--debug-extra-wait": options.debugExtraWait = true
        case "--debug-extra-arg": options.debugExtraArguments.append(value(for: argument))
        case "--device": options.devicePath = value(for: argument)
        case "--udid": options.udid = value(for: argument)
        case "--device-type":
            let id = value(for: argument)
            guard let type = DeviceType.named(id) else {
                die("--device-type needs one of: \(DeviceType.all.map(\.id).joined(separator: ", ")) (not '\(id)')", status: 64)
            }
            options.deviceType = type
        case "--debug-bootstrap-discard": options.debugBootstrapDiscard = true
        case "--host-bootstrap": options.hostBootstrap = true
        case "--job-path": options.jobPaths.append(value(for: argument))
        case "--oneshot":
            let argv = splitCommandLine(value(for: argument))
            guard let program = argv.first, program.hasPrefix("/") else { die("--oneshot needs \"/guest/program [arg]...\"", status: 64) }
            options.oneshots.append(argv)
        case "--runtime-job": options.runtimeJobs.append(value(for: argument))
        case "--runtime-paths": options.runtimePaths = true
        case "--debug-thread-report": options.debugThreadReport = true
        case "--debug-no-session-end": options.debugNoSessionEnd = true
        case "--debug-no-host-services": options.debugNoHostServices = true
        case "--debug-no-metal": options.debugNoMetal = true
        case "--metal-translator": options.metalTranslator = value(for: argument)
        case "--gpu-cache-dir": options.gpuCacheDirectory = value(for: argument)
        case "--no-gpu-cache": options.noGPUCache = true
        case "--screenshot": options.screenshotPath = value(for: argument)
        case "--display": options.screenshotDisplay = value(for: argument)
        case let a where a.hasPrefix("--display="): options.screenshotDisplay = String(a.dropFirst("--display=".count))
        case "--display-server":
            guard let address = DisplayAddress(value(for: argument)) else {
                die("--display-server needs unix:<path>, <host>:<port>, or <port>", status: 64)
            }
            options.displayServer = address
        case "--hid-bundle": options.hidBundle = value(for: argument)
        case "--room":
            let room = value(for: argument)
            guard VisionRooms.isValidKey(room) else { die("--room needs a room key (\(VisionRooms.known.joined(separator: ", ")))", status: 64) }
            options.visionRoom = room
        case "--skip-first-boot-migration": options.skipFirstBootMigration = true
        case "--screenshot-at":
            guard let n = Int(value(for: argument)), n > 0 else { die("--screenshot-at needs seconds > 0", status: 64) }
            options.screenshotTimes.append(n)
        case "--install-app": options.installApp = value(for: argument)
        case "--launch": options.launchBundleID = value(for: argument)
        case "--app-arg": options.appArguments.append(value(for: argument))
        case "--app-url": options.appURL = value(for: argument)
        case "--app-env":
            let pair = value(for: argument)
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { die("--app-env needs K=V", status: 64) }
            options.appEnvironment.append(pair)
        case "--guest-tools": options.guestTools = value(for: argument)
        case "--settings-agent": options.settingsAgent = value(for: argument)
        case "--pairing-agent": options.pairingAgent = value(for: argument)
        case "--health-agent": options.healthAgent = value(for: argument)
        case "--environment-overrides": options.environmentOverrides = true
        case "--profile": options.profile = GaugeOptions(path: absolutePath(value(for: argument)))
        case "--debug-server": options.debugServer = DebugServerOptions(address: value(for: argument))
        case "--debug-server-log":
            guard options.debugServer != nil else { die("--debug-server-log needs --debug-server first", status: 64) }
            options.debugServer?.log = true
        case "--debug-launch-stopped":
            guard options.debugServer != nil else { die("--debug-launch-stopped needs --debug-server first", status: 64) }
            options.debugServer?.launchStopped = true
        case "--profile-rate", "--profile-hang-ms", "--profile-seconds", "--profile-process":
            let v = value(for: argument)
            guard options.profile != nil else { die("\(argument) needs --profile first", status: 64) }
            switch argument {
            case "--profile-rate":
                guard let n = Int(v), (10...10_000).contains(n) else { die("--profile-rate needs 10...10000", status: 64) }
                options.profile?.rate = n
            case "--profile-hang-ms":
                guard let n = Int(v), n > 0 else { die("--profile-hang-ms needs a positive integer", status: 64) }
                options.profile?.hangMilliseconds = n
            case "--profile-seconds":
                guard let s = Double(v), s > 0 else { die("--profile-seconds needs a positive number", status: 64) }
                options.profile?.seconds = s
            default: options.profile?.processes.append(v)
            }
        case "--profile-no-signposts":
            guard options.profile != nil else { die("--profile-no-signposts needs --profile first", status: 64) }
            options.profile?.signposts = false
        case "--framebuffer-library": options.framebufferLibrary = value(for: argument)
        case "--camera": options.camera = value(for: argument)
        case "--vision-display":
            let v = value(for: argument)
            guard v.split(separator: "x").compactMap({ Int($0) }).count == 2 else { die("--vision-display needs <width>x<height>", status: 64) }
            setenv("SWIFTCODE_VISION_SCREEN", v, 1)
        case "--camera-position": options.cameraPosition = value(for: argument)
        case "--camera-library": options.cameraLibrary = value(for: argument)
        case "--debug-host-identity":
            let parts = value(for: argument).split(separator: ":").compactMap { Int64($0) }
            guard parts.count == 3 else { die("--debug-host-identity needs PID:UID:GID", status: 64) }
            options.debugHostIdentity = (Int32(parts[0]), UInt32(parts[1]), UInt32(parts[2]))
        case "--trace-name": options.traceNames.insert(value(for: argument))
        case "--trace-pid":
            guard let n = Int32(value(for: argument)) else { die("--trace-pid needs a pid", status: 64) }
            options.tracePIDs.insert(n)
        case "--oneshot-delay":
            guard let n = Int(value(for: argument)), n > 0 else { die("--oneshot-delay needs seconds > 0", status: 64) }
            options.oneshotDelay = n
        case "--debug-plist-bool":
            let parts = value(for: argument).split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, let flag = Bool(parts[1]) else { die("--debug-plist-bool needs KEY=true|false", status: 64) }
            options.plistBoolOverrides[parts[0]] = flag
        case "--env":
            let pair = value(for: argument)
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { die("--env needs K=V", status: 64) }
            options.environment.append(pair)
        case "--exec-args":
            while let rest = iterator.next() { options.execArguments.append(rest) }
        case "--max-exits":
            guard let n = Int(value(for: argument)), n > 0 else { die("--max-exits needs a positive integer", status: 64) }
            options.maxExits = n
        case "-h", "--help":
            print(usage)
            exit(0)
        case "--list-device-types":
            for type in DeviceType.all { print(type.id) }
            exit(0)
        default:
            die("unknown argument '\(argument)'\n\(usage)", status: 64)
        }
    }
    return options
}

func readFile(_ path: String) -> [UInt8] {
    guard let file = fopen(path, "rb") else { die("cannot open \(path): \(String(cString: strerror(errno)))", status: 66) }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = fread(&buffer, 1, buffer.count, file)
        if n > 0 { bytes.append(contentsOf: buffer[0..<n]) }
        if n < buffer.count {
            if ferror(file) != 0 { die("cannot read \(path)", status: 66) }
            break
        }
    }
    return bytes
}

func dumpVCPU(_ vcpu: VCPU) {
    var parts: [String] = []
    func add(_ name: String, _ read: () throws -> UInt64) {
        if let value = try? read() { parts.append("\(name)=\(hex(value))") } else { parts.append("\(name)=?") }
    }
    add("pc") { try vcpu.get(.pc) }
    add("pstate") { try vcpu.get(.pstate) }
    add("sp_el1") { try vcpu.get(.spEL1) }
    add("elr_el1") { try vcpu.get(.elrEL1) }
    add("spsr_el1") { try vcpu.get(.spsrEL1) }
    add("esr_el1") { try vcpu.get(.esrEL1) }
    add("far_el1") { try vcpu.get(.farEL1) }
    add("vbar_el1") { try vcpu.get(.vbarEL1) }
    add("sctlr_el1") { try vcpu.get(.sctlrEL1) }
    stderrLine("swiftcode-simd: vCPU state: " + parts.joined(separator: " "))
    if let esr = try? vcpu.get(.esrEL1) {
        stderrLine("swiftcode-simd: ESR_EL1 EC=\(hex((esr >> 26) & 0x3F)) IL=\((esr >> 25) & 1) ISS=\(hex(esr & 0x1FF_FFFF))")
    }
}

let initialTPIDRRO: UInt64 = 0x0000_0001_5943_0000

func runStage2(_ options: Options) throws -> Never {
    guard let shimPath = options.shimPath, let el0Path = options.el0Path else { die("missing --shim or --el0\n\(usage)", status: 64) }
    let timeout = options.timeoutMilliseconds ?? 10_000
    let maxExits = options.maxExits ?? 100_000
    let shim = readFile(shimPath)
    let el0Image = readFile(el0Path)
    guard !shim.isEmpty, UInt64(shim.count) <= VMLayout.shimRegionSize else {
        die("shim image is empty or larger than \(VMLayout.shimRegionSize) bytes", status: 66)
    }
    guard !el0Image.isEmpty else { die("EL0 image is empty", status: 66) }

    let vm = try VirtualMachine(ramGPA: VMLayout.ramGPA, ramSize: Int(VMLayout.ramSize))

    var tables = PageTableBuilder(tableArenaGPA: VMLayout.pageTableArenaGPA, tableArenaSize: Int(VMLayout.pageTableArenaSize))
    for region in VMLayout.el1Regions { try tables.mapIdentity(region) }
    let multi = options.vcpus != nil
    if multi { try tables.mapIdentity(VCPUSlots.region) }
    var nextPoolGPA = multi ? VCPUSlots.baseGPA + VCPUSlots.regionSize : VMLayout.el0PoolGPA
    for region in VMLayout.selfTestRegions(imageSize: UInt64(el0Image.count)) {
        guard nextPoolGPA + region.size <= VMLayout.el0PoolGPA + VMLayout.el0PoolSize else {
            die("EL0 pool exhausted mapping \(region.name)", status: 66)
        }
        try tables.map(va: region.va, pa: nextPoolGPA, size: region.size, attributes: region.attributes)
        if options.trace {
            stderrLine("swiftcode-simd: map \(region.name) va \(hex(region.va))-\(hex(region.end)) -> pa \(hex(nextPoolGPA)) \(region.attributes)")
        }
        nextPoolGPA += region.size
    }
    for table in tables.tables { try vm.write(gpa: table.gpa, bytes: table.bytes) }

    try vm.write(gpa: VMLayout.shimGPA, bytes: shim)
    let loader = TranslatedGuestMemory(vm: vm, pageTables: tables, enforceEL0Permissions: false)
    try loader.write(va: VMLayout.selfTestImageVA, bytes: el0Image)

    let bootInfo = BootInfo(
        ttbr0EL1: tables.rootGPA,
        el0EntryPC: VMLayout.selfTestImageVA,
        el0InitialSP: VMLayout.el0StackTop,
        trapFrameAddress: VMLayout.trapFrameGPA,
        doorbellAddress: VMLayout.doorbellGPA,
        tpidrroEL0: initialTPIDRRO,
        tpidrEL0: 0,
        el0Registers: [initialTPIDRRO, UInt64(VMLayout.guestPID), 0, 0, 0, 0, 0, 0],
        el1StackTop: VMLayout.el1StackTop)
    try vm.write(gpa: VMLayout.bootInfoGPA, bytes: bootInfo.encoded())
    if options.trace {
        stderrLine("swiftcode-simd: \(tables.tables.count) table pages, root \(hex(tables.rootGPA)); shim \(shim.count) bytes; EL0 image \(el0Image.count) bytes")
    }

    if let count = options.vcpus {
        try runStage2Pool(options, vm: vm, tables: tables, shimSize: shim.count, count: count, timeout: timeout, maxExits: maxExits)
    }

    let vcpu = try vm.makeVCPU()
    try vcpu.set(.pc, VMLayout.shimEntryGPA)
    try vcpu.set(.pstate, VMLayout.el1BootPSTATE)
    try vcpu.set(.x(0), VMLayout.bootInfoGPA)

    let memory = TranslatedGuestMemory(vm: vm, pageTables: tables)
    var dispatcher = DarwinTrapDispatcher(
        pid: VMLayout.guestPID,
        stdout: { text in writeFD(1, text) },
        stderr: { text in writeFD(2, text) },
        log: { line in stderrLine("[trap] " + line) })

    try Watchdog.arm(milliseconds: timeout)
    while true {
        guard vcpu.exitCount < maxExits else {
            dumpVCPU(vcpu)
            die("guest exceeded \(maxExits) VM exits", status: 71)
        }
        let exit = try vcpu.run()
        if options.trace { stderrLine("swiftcode-simd: exit #\(vcpu.exitCount): \(exit)") }

        switch exit {
        case let .mmio(.write, address, frameAddress, 8) where address == VMLayout.doorbellGPA:
            guard frameAddress == VMLayout.trapFrameGPA else {
                dumpVCPU(vcpu)
                die("doorbell carried frame address \(hex(frameAddress)), expected \(hex(VMLayout.trapFrameGPA))", status: 71)
            }
            var frame = try TrapFrame(decoding: vm.read(gpa: frameAddress, count: TrapFrame.byteCount))
            let outcome = dispatcher.handle(&frame, memory: memory)
            switch outcome {
            case .resume:
                try vm.write(gpa: frameAddress, bytes: frame.encoded())
            case let .exit(status):
                if options.trace { stderrLine("swiftcode-simd: guest exited with status \(status) after \(vcpu.exitCount) VM exits") }
                Glibc.exit(status)
            case let .fatal(message):
                die("fatal guest trap:\n\(message)", status: VMLayout.fatalExitStatus)
            }
        case .watchdog:
            dumpVCPU(vcpu)
            die("watchdog: guest still running after \(timeout) ms", status: 71)
        default:
            dumpVCPU(vcpu)
            die("unexpected VM exit: \(exit)", status: 71)
        }
    }
}

func runStage2Pool(_ options: Options, vm: VirtualMachine, tables: PageTableBuilder, shimSize: Int,
                   count: Int, timeout: UInt64, maxExits: Int) throws -> Never {
    let pool = try VCPUPool(vm: vm, bootTemplate: BootInfo(ttbr0EL1: tables.rootGPA, el0EntryPC: 0),
                            limit: VCPUSlots.lowCount, maxExitsPerVCPU: maxExits)
    stderrLine("swiftcode-simd: KVM_CAP_MAX_VCPUS \(vm.maxVCPUs), KVM_CAP_NR_VCPUS \(vm.recommendedVCPUs); pool capacity \(pool.capacity)")
    guard count <= pool.capacity else { die("--vcpus \(count) exceeds the pool capacity \(pool.capacity)", status: 64) }
    pool.preBootCleanRanges = { [(VMLayout.shimGPA, shimSize), (tables.rootGPA, tables.tables.count * Int(VMLayout.pageSize))] }
    if options.trace { pool.log = { stderrLine("swiftcode-simd: " + $0) } }
    let memory = TranslatedGuestMemory(vm: vm, pageTables: tables)
    let lock = HostMutex()
    var finished = 0
    var dispatcher = DarwinTrapDispatcher(
        pid: VMLayout.guestPID,
        stdout: { text in writeFD(1, text) },
        stderr: { text in writeFD(2, text) },
        log: { line in if options.trace { stderrLine("[trap] " + line) } })
    pool.trapHandler = { worker, frame in
        let outcome = lock.withLock { dispatcher.handle(&frame, memory: memory) }
        switch outcome {
        case .resume:
            return .resume
        case let .exit(status) where status == 0:
            lock.withLock { finished += 1 }
            return .park
        case let .exit(status):
            return .terminate(status: status, message: "vCPU \(worker.index): self-test exited with status \(status)")
        case let .fatal(message):
            return .terminate(status: VMLayout.fatalExitStatus, message: "vCPU \(worker.index): fatal guest trap:\n\(message)")
        }
    }
    let state = VCPUStartState(pc: VMLayout.selfTestImageVA, sp: VMLayout.el0StackTop,
                                 registers: [initialTPIDRRO, UInt64(VMLayout.guestPID)], tpidrro: initialTPIDRRO)
    var started = Date()
    for round in 1...options.rounds {
        for _ in 0..<count {
            guard try pool.start(state, context: nil) != nil else { die("round \(round): the vCPU pool is exhausted", status: 71) }
        }
        while true {
            if let end = pool.currentTermination { die(end.message, status: end.status) }
            if lock.withLock({ finished }) == round * count && pool.parkedCount == count { break }
            if Date().timeIntervalSince(started) * 1000 > Double(timeout) {
                let report = pool.stopAll()
                die("watchdog: round \(round) still running after \(timeout) ms\n\(report)", status: 71)
            }
            usleep(500)
        }
        stderrLine("swiftcode-simd: round \(round): \(count) threads exited 0 on \(pool.vcpuCount) vCPUs")
        started = Date()
    }
    stderrLine("swiftcode-simd: multi-vCPU self-test ok (\(count) vCPUs x \(options.rounds) rounds)")
    exit(0)
}

if CommandLine.arguments.contains("--device"), getenv("SWIFTCODE_BOOT_PRIORITY").map({ String(cString: $0) != "0" }) ?? true,
   getenv("SWIFTCODE_SCHED_QOS") == nil {
    setenv("SWIFTCODE_SCHED_QOS", "1", 0)
    setenv("SWIFTCODE_HOST_SCHED", "cgroup", 0)
    SchedPolicy.qosEnabled = true
}
if isHealthClient(CommandLine.arguments) { runHealthClient(CommandLine.arguments) }
if isSettingsClient(CommandLine.arguments) { runSettingsClient(CommandLine.arguments) }
if isPairingCommand(CommandLine.arguments) { runPairingCommand(CommandLine.arguments) }
if isControlClient(CommandLine.arguments) { runControlClient(CommandLine.arguments) }
if isPrivacyClient(CommandLine.arguments) { runPrivacyClient(CommandLine.arguments) }
HostSched.prepareProcess()
SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-simd")
var options = parseOptions(CommandLine.arguments)
if !VCPUPool.hostHasDIC { GuestAddressSpace.flushOnAdditions = true }
if getenv("SWIFTCODE_EXIT_WITH_PARENT").map({ String(cString: $0) == "1" }) ?? false {
    _ = ckvm_signal_on_parent_death(SIGTERM)
}
if let n = getenv("SWIFTCODE_DEBUG_MEMCHECK").flatMap({ Int(String(cString: $0)) }), n > 0 {
    HardwareWatchpoint.startMemoryCheck(threads: n)
    stderrLine("swiftcode-simd: debug: \(n) lost-write checker threads")
}
if DebugAccessGuard.enabled {
    HardwareWatchpoint.installFrameCapture()
    stderrLine("swiftcode-simd: debug: reader/writer check on interval maps")
}
if getenv("SWIFTCODE_DEBUG_HWWATCH").map({ String(cString: $0) == "1" }) ?? false {
    DebugHardwareWatch.arm = { HardwareWatchpoint.arm($0, $1) }
    DebugHardwareWatch.disarm = { HardwareWatchpoint.disarm($0) }
    stderrLine("swiftcode-simd: debug: hardware write watch on allocator map elements")
}
var gpuCacheDirectory = options.gpuCacheDirectory
if gpuCacheDirectory == nil, !options.noGPUCache, options.devicePath != nil, !options.debugNoMetal,
   getenv("SWIFTCODE_VULKAN_PIPELINE_CACHE") == nil, getenv("SWIFTCODE_AIRC_CACHE") == nil {
    let env = ProcessInfo.processInfo.environment
    let base = env["XDG_CACHE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil }
        ?? (env["HOME"].map { $0 + "/.cache" } ?? NSTemporaryDirectory())
    gpuCacheDirectory = base + "/swiftcode/gpu"
}
if let dir = gpuCacheDirectory, !options.noGPUCache {
    let absolute = dir.hasPrefix("/") ? dir : FileManager.default.currentDirectoryPath + "/" + dir
    do {
        try FileManager.default.createDirectory(atPath: absolute + "/airc", withIntermediateDirectories: true)
    } catch {
        die("--gpu-cache-dir: cannot create \(absolute): \(error)", status: 66)
    }
    setenv("SWIFTCODE_VULKAN_PIPELINE_CACHE", absolute + "/vulkan-pipelines.bin", 1)
    setenv("SWIFTCODE_AIRC_CACHE", absolute + "/airc", 1)
}
do {
    if options.kvmSmoke {
        try KVMSmokeTest.run { print($0) }
        exit(0)
    }
    if let macOS = options.macOSPath {
        guard options.execPath == nil, options.devicePath == nil else { die("--macos excludes --exec and --device", status: 64) }
        MacOSMode.enabled = true
        options.execPath = macOS
    }
    if options.execPath != nil || options.devicePath != nil {
        try runExec(options)
    }
    try runStage2(options)
} catch {
    die("\(error)", status: 1)
}
#else
print("swiftcode-simd: the micro-VM needs Linux with KVM (arm64)")
#endif
