import Foundation

struct DeviceLayout {
    let dev: String
    var guestDev: String
    let runtimeRoot: String
    let udid: String
    let jobPaths: [String]
    let bootTime: Int
    let oneshots: [[String]]
    let runtimeJobs: [String]
    var plistBoolOverrides: [String: Bool] = [:]
    var oneshotDelay: Int?
    var installApp: String?
    var launchBundleID: String?
    var appArguments: [String] = []
    var appURL: String?
    var appEnvironment: [String] = []
    var guestTools: String?
    var framebufferLibrary: String?
    var hidBundle: String?
    var settingsAgent: String?
    var pairingAgent: String?
    var healthAgent: String?
    var overridesLibrary: String?
    var gaugeLibrary: String?
    var skipFirstBootMigration = false
    var lean: LeanBootProfile? = LeanBootProfile.fromProcessEnvironment
    var templatePath: String? = ProcessInfo.processInfo.environment["SWIFTCODE_DEVICE_TEMPLATE"].flatMap { $0.isEmpty ? nil : $0 }
    var restoring = false
    var deviceType: DeviceType = .default

    static let deviceName = "SwiftCode"

    init(dev: String, runtimeRoot: String, udid: String?, jobPaths: [String], runtimePaths: Bool = false,
         oneshots: [[String]] = [], runtimeJobs: [String] = [], bootTime: Int = Int(Date().timeIntervalSince1970)) {
        self.dev = dev
        self.guestDev = dev
        self.runtimeRoot = runtimeRoot
        self.udid = udid?.uppercased() ?? Self.stableUDID(for: dev)
        self.oneshots = oneshots
        self.runtimeJobs = runtimeJobs
        let swiftcodeJobs = runtimeJobs.isEmpty ? [] : [dev + "/swiftcode-jobs"]
        let coreSimulatorPaths = runtimePaths
            ? ["/System/Library/LaunchDaemons", "/System/Library/LaunchAngels", "/Developer/Library/LaunchDaemons"]
                .map { runtimeRoot + $0 } + [dev + "/data/Library/LaunchDaemons"]
            : []
        let paths = coreSimulatorPaths + jobPaths + swiftcodeJobs
        self.jobPaths = paths.isEmpty ? [dev + "/swiftcode-empty-jobs"] : paths
        self.bootTime = bootTime
    }

    var data: String { dev + "/data" }
    func guestPath(_ hostPath: String) -> String {
        if guestDev == dev { return hostPath }
        if hostPath == dev { return guestDev }
        if hostPath.hasPrefix(dev + "/") { return guestDev + hostPath.dropFirst(dev.count) }
        return hostPath
    }
    var guestData: String { guestPath(data) }
    var varRun: String { data + "/var/run" }
    var plistPath: String { varRun + "/launchd_bootstrap.plist" }
    var audioPlistPath: String { varRun + "/com.apple.coresimulator.audio.plist" }
    var audioSettingsPath: String { varRun + "/simulatoraudio/audiosettings.plist" }
    var memoryWarningPath: String { varRun + "/memory_warning_simulation" }
    var capabilitiesPath: String { dev + "/swiftcode-capabilities.plist" }
    var extendedDisplayPath: String { data + "/Library/Application Support/Simulator/extended_display.plist" }
    var deviceTypePath: String { dev + "/swiftcode-device-type" }
    var runtimeRecordPath: String { dev + "/swiftcode-runtime" }
    var globalPreferencesPath: String { data + "/Library/Preferences/.GlobalPreferences.plist" }
    static var firstBootGlobalPreferences: [String: Any] { ["AppleLanguages": ["en-US"], "AppleLocale": "en_US"] }
    var logRoot: String { dev + "/Logs" }
    var launchdName: String { "com.apple.CoreSimulator.SimDevice.\(udid)" }
    var tmpGuestPath: String { "/private/var/tmp/" + launchdName }
    var disabledOverridesHostPath: String { tmpHostPath + "/disabled.plist" }
    var privateVarTmpHostPath: String { dev + "/private-var-tmp" }
    var tmpHostPath: String { privateVarTmpHostPath + "/" + launchdName }
    var hostBootstrapLogPath: String { dev + "/swiftcode-host-bootstrap.log" }
    var launchdSimPath: String { runtimeRoot + "/sbin/launchd_sim" }
    var swiftcodeJobsPath: String { dev + "/swiftcode-jobs" }

    var hidGuestPath: String? { hidBundle.map { _ in dev + "/swiftcode-frameworks/SimHID.framework" } }
    var hidLogPath: String { data + "/tmp/swiftcode-simhid.log" }

    var framebufferStatePath: String { memoryFile("swiftcode-framebuffer.state").host }
    var framebufferStateGuestPath: String { memoryFile("swiftcode-framebuffer.state").guest }
    static let displayTiming: Bool = ProcessInfo.processInfo.environment["SWIFTCODE_DISPLAY_TIMING"] == "1"
    var framebufferTimingPath: String { memoryFile("swiftcode-framebuffer.timing").guest }
    var hidTimingPath: String { memoryFile("swiftcode-simhid.timing").guest }
    var displayTracePath: String { memoryFile("swiftcode-display.trace").host }

    var framebufferGuestPath: String? {
        framebufferLibrary.map { _ in dev + "/swiftcode-frameworks/SimFramebuffer.framework/SimFramebuffer" }
    }

    var appsDirectory: String { data + "/tmp/swiftcode-apps" }
    var stagedAppGuestPath: String? {
        installApp.map { appsDirectory + "/" + (($0 as NSString).standardizingPath as NSString).lastPathComponent }
    }
    var ylaunchPath: String? { installApp != nil || launchBundleID != nil ? data + "/tmp/swiftcode-tools/ylaunch" : nil }
    static let appStdoutGuestPath = "/tmp/swiftcode-app.out"
    static let appStderrGuestPath = "/tmp/swiftcode-app.err"
    var appStdoutHostPath: String { data + Self.appStdoutGuestPath }
    var appStderrHostPath: String { data + Self.appStderrGuestPath }

    func oneshotLabel(_ index: Int) -> String {
        "com.swiftcode.oneshot.\(index + 1).\((oneshots[index].first.map { ($0 as NSString).lastPathComponent }) ?? "job")"
    }

    func oneshotOutputGuestPath(_ index: Int, err: Bool) -> String {
        "/tmp/swiftcode-oneshot-\(index + 1).\(err ? "err" : "out")"
    }

    func oneshotOutputHostPath(_ index: Int, err: Bool) -> String {
        data + "/tmp/swiftcode-oneshot-\(index + 1).\(err ? "err" : "out")"
    }

    func oneshotProgram(_ index: Int) -> String {
        let program = oneshots[index].first ?? "/"
        if program.hasPrefix(dev + "/") { return guestPath(program) }
        if program.hasPrefix(guestDev + "/") || program.hasPrefix(runtimeRoot + "/") { return program }
        return runtimeRoot + program
    }

    var runtimeJobDirectories: [String] {
        ["/System/Library/LaunchDaemons", "/System/Library/LaunchAngels", "/Developer/Library/LaunchDaemons"].map { runtimeRoot + $0 }
    }

    func runtimeJobPlist(_ label: String) -> String? {
        let file = label.hasSuffix(".plist") ? label : label + ".plist"
        return runtimeJobDirectories.map { $0 + "/" + file }.first { FileManager.default.fileExists(atPath: $0) }
    }

    var displayUID: String? {
        if let uid = deviceType.displayUID { return uid }
        return deviceType.family == .watch ? Self.displayUID(forDevice: udid) : nil
    }

    static func displayUID(forDevice udid: String) -> String {
        let h = stableUDID(for: "display-1:" + udid.uppercased())
        return "59434F44" + h.dropFirst(8)
    }

    static func stableUDID(for path: String) -> String {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h = seed
            for b in path.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
            return h
        }
        var bytes = withUnsafeBytes(of: fnv(0xCBF2_9CE4_8422_2325).bigEndian, Array.init)
            + withUnsafeBytes(of: fnv(0x84222325CBF29CE4).bigEndian, Array.init)
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hexText = bytes.map { String(format: "%02X", $0) }.joined()
        let c = Array(hexText)
        return [String(c[0..<8]), String(c[8..<12]), String(c[12..<16]), String(c[16..<20]), String(c[20..<32])].joined(separator: "-")
    }

    func runtimeVersion() -> (version: String, build: String) {
        let path = runtimeRoot + "/System/Library/CoreServices/SystemVersion.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return ("", "")
        }
        return (plist["ProductVersion"] as? String ?? "", plist["ProductBuildVersion"] as? String ?? "")
    }

    func runtimePlatform() -> RuntimePlatform {
        let path = runtimeRoot + "/System/Library/CoreServices/SystemVersion.plist"
        let plist = FileManager.default.contents(atPath: path).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any]
        }
        return RuntimePlatform(productName: plist?["ProductName"] as? String)
    }

    var childDefaults: [String: String] {
        [
            "CFFIXED_USER_HOME": guestData,
            "HOME": guestData,
            "TMPDIR": guestData + "/tmp/",
            "DYLD_FALLBACK_FRAMEWORK_PATH": runtimeRoot + "/System/Library/Frameworks",
            "DYLD_FALLBACK_LIBRARY_PATH": runtimeRoot + "/usr/lib",
        ]
    }

    var child: [String: String] {
        let rr = runtimeRoot
        let (version, build) = runtimeVersion()
        func decimal(_ v: Double) -> String { String(format: "%f", v) }
        var env = [
            "DYLD_ROOT_PATH": rr,
            "IPHONE_SIMULATOR_ROOT": rr,
            "SIMULATOR_ROOT": rr,
            "DYLD_SHARED_CACHE_DIR": rr + "/System/Library/Caches/com.apple.dyld",
            "PATH": "\(rr)/usr/bin:\(rr)/bin:\(rr)/usr/sbin:\(rr)/sbin:\(rr)/usr/local/bin",
            "IPHONE_SHARED_RESOURCES_DIRECTORY": guestData,
            "SIMULATOR_SHARED_RESOURCES_DIRECTORY": guestData,
            "XPC_SIMULATOR_LAUNCHD_NAME": launchdName,
            "LS_ENABLE_BUNDLE_LOCALIZATION_CACHING": "1",
            "SIMULATOR_UDID": udid,
            "SIMULATOR_DEVICE_NAME": Self.deviceName,
            "SIMULATOR_MODEL_IDENTIFIER": deviceType.modelIdentifier,
            "SIMULATOR_PRODUCT_CLASS": deviceType.productClass,
            "SIMULATOR_LEGACY_ASSET_SUFFIX": deviceType.legacyAssetSuffix,
            "SIMULATOR_MAINSCREEN_WIDTH": String(deviceType.screen.width),
            "SIMULATOR_MAINSCREEN_HEIGHT": String(deviceType.screen.height),
            "SIMULATOR_MAINSCREEN_SCALE": decimal(deviceType.screen.scale),
            "SIMULATOR_MAINSCREEN_PITCH": decimal(deviceType.screen.pitch),
            "SIMULATOR_CAPABILITIES": guestPath(capabilitiesPath),
            "SIMULATOR_RUNTIME_VERSION": version,
            "SIMULATOR_RUNTIME_BUILD_VERSION": build,
            "SIMULATOR_ARCHS": "arm64",
            "SIMULATOR_VERSION_INFO": "SwiftCode - Device: \(Self.deviceName) (\(udid)) - Runtime: \(runtimePlatform().displayName) \(version) (\(build)) - DeviceType: \(deviceType.modelIdentifier)",
            "SIMULATOR_BOOT_TIME": String(bootTime),
            "SIMULATOR_HOST_HOME": guestDev,
            "SIMULATOR_LOG_ROOT": guestPath(logRoot),
            "SIMULATOR_FRAMEBUFFER_FRAMEWORK": framebufferGuestPath.map(guestPath) ?? "",
            "SWIFTCODE_FRAMEBUFFER_STATE": framebufferStateGuestPath,
            "SWIFTCODE_FRAMEBUFFER_TIMING": Self.displayTiming ? framebufferTimingPath : "",
            "SWIFTCODE_SIMHID_TIMING": Self.displayTiming && hidGuestPath != nil ? hidTimingPath : "",
            "SWIFTCODE_FRAMEBUFFER_COMPLETION": ProcessInfo.processInfo.environment["SWIFTCODE_FRAMEBUFFER_COMPLETION"] ?? "",
            "SIMULATOR_HID_SYSTEM_MANAGER": hidGuestPath.map(guestPath) ?? "",
            "SWIFTCODE_SIMHID_LOG": hidGuestPath == nil ? "" : guestPath(hidLogPath),
            "SIMULATOR_AUDIO_DEVICES_PLIST_PATH": guestPath(audioPlistPath),
            "SIMULATOR_AUDIO_SETTINGS_PATH": guestPath(audioSettingsPath),
            "SIMULATOR_MEMORY_WARNINGS": guestPath(memoryWarningPath),
        ]
        if let uid = displayUID { env["SWIFTCODE_FRAMEBUFFER_DISPLAY_UID"] = uid }
        if deviceType.features.contains("com.apple.hid.digital-crown") {
            env["SWIFTCODE_SIMHID_DIGITAL_CROWN"] = "1"
            if deviceType.features.contains(DeviceType.actionButtonFeature) { env["SWIFTCODE_SIMHID_ACTION_BUTTON"] = "1" }
        }
        if runtimePlatform() == .visionOS { env["SWIFTCODE_SIMHID_VISION"] = "1" }
        if deviceType.isFoldable {
            env["SWIFTCODE_SIMHID_DEVICE_MOTION"] = "1"
            if let second = deviceType.publishedSecondDisplay { env["SWIFTCODE_FRAMEBUFFER_SECOND_DISPLAY"] = second.environmentValue }
        }
        if ProcessInfo.processInfo.environment["SWIFTCODE_FRAMEBUFFER_CALLS"] == "1" {
            env["SWIFTCODE_FRAMEBUFFER_CALLS"] = guestPath(data + "/tmp/swiftcode-framebuffer.calls")
        }
        if ProcessInfo.processInfo.environment["SWIFTCODE_FRAMEBUFFER_LIVE_SIZE"] == "1" {
            env["SWIFTCODE_FRAMEBUFFER_LIVE_SIZE"] = guestPath(data + "/tmp/swiftcode-framebuffer.live-size")
        }
        if let extra = ProcessInfo.processInfo.environment["SWIFTCODE_CHILD_ENV"] {
            for pair in extra.split(separator: ";") {
                guard let eq = pair.firstIndex(of: "=") else { continue }
                env[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
            }
        }
        if deviceType.extendedDisplayProperties {
            env["SIMULATOR_EXTENDED_DISPLAY_PROPERTIES"] = guestPath(extendedDisplayPath)
            env["IPHONE_TVOUT_EXTENDED_PROPERTIES"] = guestPath(extendedDisplayPath)
        }
        return env
    }

    var selfEnvironment: [String: String] { child.merging(childDefaults) { a, _ in a } }

    func launchdEnvironment(overrides: [String]) -> [String] {
        var env = selfEnvironment
        env["XPC_SERVICE_NAME"] = launchdName
        env["XPC_FLAGS"] = "0x0"
        env["OSLogRateLimit"] = "64"
        env["USER"] = "mobile"
        env["LOGNAME"] = "mobile"
        env["SHELL"] = "/bin/sh"
        env["__CF_USER_TEXT_ENCODING"] = "0x1F5:0x0:0x0"
        for pair in overrides {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            env[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        return env.keys.sorted().map { "\($0)=\(env[$0]!)" }
    }

    var bootstrapPlist: [String: Any] {
        var plist: [String: Any] = [
            "Bootstrap": [
                "SimulatorRuntimeRoot": runtimeRoot,
                "Paths": jobPaths.map(guestPath),
                "Self": selfEnvironment,
                "Child": child,
                "ChildDefaults": childDefaults,
                "BinaryOrderPreference": "arm64",
                "CheckedAllocationsPosixSpawnFlagsGlobal": false,
            ] as [String: Any],
            "AbortOnUnknownIPC": true,
            "CrashOnSIGTERMTimeout": true,
            "ExtensionWatchdog": 0,
            "LogServiceLifecycle": true,
            "LogToFlatFile": true,
            "RequireDomainBinding": true,
            "SIGTERMTimeout": 3,
            "UseGuardMalloc": false,
        ]
        for (key, value) in plistBoolOverrides { plist[key] = value }
        return plist
    }

    func prepare() throws {
        let fm = FileManager.default
        func dir(_ path: String, mode: Int = 0o755) throws {
            try fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
            try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
        }
        try checkDeviceType()
        try checkRuntime()
        let isNewDevice = Self.recordedDeviceType(in: dev) == nil || !fm.fileExists(atPath: plistPath)
        if restoring {
            try prepareMemoryDirectory()
            try stageApp(dir)
            try stageOverridesLibrary()
            try stageGaugeLibrary()
            return
        }
        if let templatePath, !fm.fileExists(atPath: data) {
            try checkTemplate(templatePath)
            try cloneData(from: templatePath)
        }
        try handleRelocation()
        for path in [dev, data, data + "/tmp", varRun, varRun + "/simulatoraudio", data + "/Library/LaunchDaemons",
                     data + "/Library/Application Support/Simulator", logRoot, privateVarTmpHostPath] {
            try dir(path)
        }
        try prepareMemoryDirectory()
        if isNewDevice && !fm.fileExists(atPath: globalPreferencesPath) {
            try dir((globalPreferencesPath as NSString).deletingLastPathComponent)
            try writeXML(Self.firstBootGlobalPreferences, to: globalPreferencesPath)
        }
        if fm.fileExists(atPath: tmpHostPath) {
            let stamp = Int((try? fm.attributesOfItem(atPath: tmpHostPath)[.modificationDate] as? Date)??.timeIntervalSince1970 ?? 0)
            try fm.moveItem(atPath: tmpHostPath, toPath: "\(tmpHostPath).previous-\(stamp)-\(bootTime)")
        }
        if let lean, !lean.disabledLabels.isEmpty {
            try dir(tmpHostPath, mode: 0o700)
            let plist = lean.disabledOverrides().mapValues { $0 as Any }
            try writeXML(plist, to: disabledOverridesHostPath)
        }
        try applyLoggingPreferences(lean?.loggingOff == true)
        if let lean { FileHandle.standardError.write(Data(("swiftcode-simd: " + lean.summary + "\n").utf8)) }
        if fm.fileExists(atPath: swiftcodeJobsPath) { try fm.removeItem(atPath: swiftcodeJobsPath) }
        for path in jobPaths where !fm.fileExists(atPath: path) { try dir(path) }
        for index in oneshots.indices {
            for err in [false, true] where fm.fileExists(atPath: oneshotOutputHostPath(index, err: err)) {
                try fm.removeItem(atPath: oneshotOutputHostPath(index, err: err))
            }
        }
        try stageApp(dir)
        if skipFirstBootMigration { try recordMigrationDone() }
        if let framebufferLibrary, let target = framebufferGuestPath {
            try dir((target as NSString).deletingLastPathComponent)
            if fm.fileExists(atPath: target) { try fm.removeItem(atPath: target) }
            try fm.copyItem(atPath: framebufferLibrary, toPath: target)
            try GuestImagePlatform.adapt(fileAt: target, for: runtimePlatform(), version: runtimeVersion().version)
        }
        if let hidBundle, let target = hidGuestPath {
            try dir((target as NSString).deletingLastPathComponent)
            if fm.fileExists(atPath: target) { try fm.removeItem(atPath: target) }
            try fm.copyItem(atPath: hidBundle, toPath: target)
            try GuestImagePlatform.adapt(fileAt: target + "/SimHID", for: runtimePlatform(), version: runtimeVersion().version)
            if fm.fileExists(atPath: hidLogPath) { try fm.removeItem(atPath: hidLogPath) }
        }
        try prepareJobsAndPlists()
        try stageSettingsAgent()
        try stagePairingAgent()
        try stageHealthAgent()
        try stageOverridesLibrary()
        try stageGaugeLibrary()
        DeviceSettingsFiles(dev: dev, guestData: guestData).resetNonPersistentAtColdBoot()
    }

    private func stageApp(_ dir: (String, Int) throws -> Void) throws {
        let fm = FileManager.default
        if let installApp {
            try dir(appsDirectory, 0o755)
            let target = stagedAppGuestPath!
            if fm.fileExists(atPath: target) { try fm.removeItem(atPath: target) }
            try fm.copyItem(atPath: installApp, toPath: target)
        }
        if let ylaunchPath {
            guard let tools = guestTools, fm.fileExists(atPath: tools + "/ylaunch") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: (guestTools ?? "?") + "/ylaunch"])
            }
            try dir((ylaunchPath as NSString).deletingLastPathComponent, 0o755)
            if fm.fileExists(atPath: ylaunchPath) { try fm.removeItem(atPath: ylaunchPath) }
            try fm.copyItem(atPath: tools + "/ylaunch", toPath: ylaunchPath)
            for path in [appStdoutHostPath, appStderrHostPath] where fm.fileExists(atPath: path) { try fm.removeItem(atPath: path) }
        }
    }

    private func prepareJobsAndPlists() throws {
        let fm = FileManager.default
        for label in runtimeJobs {
            guard let source = runtimeJobPlist(label) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: runtimeRoot + "/…/" + label + ".plist"])
            }
            try fm.copyItem(atPath: source, toPath: swiftcodeJobsPath + "/" + (source as NSString).lastPathComponent)
        }
        if !fm.fileExists(atPath: memoryWarningPath) {
            guard fm.createFile(atPath: memoryWarningPath, contents: Data()) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: memoryWarningPath])
            }
        }
        try DeviceSettingsFiles(dev: dev, guestData: guestData).writeAudio(DeviceSettingsFiles(dev: dev).audio())
        try writeXML(DeviceCapabilities.plist(for: deviceType), to: capabilitiesPath)
        try writeXML(bootstrapPlist, to: plistPath)
        if recordedDeviceType() == nil { try Data((deviceType.id + "\n").utf8).write(to: URL(fileURLWithPath: deviceTypePath)) }
        try recordRuntime()
    }

    struct RuntimeRecord: Equatable {
        var productName: String
        var version: String
        var build: String
        var line: String { "\(productName) \(version) \(build)\n" }
        init(productName: String, version: String, build: String) {
            self.productName = productName.isEmpty ? "iPhone OS" : productName
            self.version = version
            self.build = build
        }
        init?(line: String) {
            let words = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
            guard words.count >= 3 else { return nil }
            self.init(productName: words.dropLast(2).joined(separator: " "), version: words[words.count - 2], build: words[words.count - 1])
        }
        var displayName: String { "\(RuntimePlatform(productName: productName).displayName) \(version) (\(build))" }
    }

    func currentRuntimeRecord() -> RuntimeRecord {
        let path = runtimeRoot + "/System/Library/CoreServices/SystemVersion.plist"
        let plist = FileManager.default.contents(atPath: path).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any]
        }
        return RuntimeRecord(productName: plist?["ProductName"] as? String ?? "", version: plist?["ProductVersion"] as? String ?? "",
                             build: plist?["ProductBuildVersion"] as? String ?? "")
    }

    static func recordedRuntime(in dev: String) -> RuntimeRecord? {
        FileManager.default.contents(atPath: dev + "/swiftcode-runtime").flatMap { RuntimeRecord(line: String(decoding: $0, as: UTF8.self)) }
    }

    static func lastSystemBuild(in dev: String) -> String? {
        let path = dev + "/data/Library/Preferences/com.apple.migration.plist"
        let plist = FileManager.default.contents(atPath: path).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }
        return plist?["LastSystemVersion"] as? String
    }

    static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    func checkRuntime() throws {
        let now = currentRuntimeRecord()
        guard !now.build.isEmpty else { return }
        if let was = Self.recordedRuntime(in: dev) {
            guard was.build != now.build else { return }
            if !was.version.isEmpty, !now.version.isEmpty, Self.compareVersions(now.version, was.version) < 0 {
                throw DeviceRuntimeDowngrade(dev: dev, recorded: was, requested: now)
            }
            FileHandle.standardError.write(Data("swiftcode-simd: warning: the device \(dev) last booted \(was.displayName); this boot of \(now.displayName) migrates its data\n".utf8))
        } else if let last = Self.lastSystemBuild(in: dev), last != now.build {
            FileHandle.standardError.write(Data("swiftcode-simd: warning: the device \(dev) was last booted on runtime build \(last), not \(now.build); this boot migrates its data\n".utf8))
        }
    }

    func recordRuntime() throws {
        let now = currentRuntimeRecord()
        guard !now.build.isEmpty, Self.recordedRuntime(in: dev) != now else { return }
        try Data(now.line.utf8).write(to: URL(fileURLWithPath: runtimeRecordPath), options: .atomic)
    }

    static func recordedDeviceType(in dev: String) -> String? {
        let fm = FileManager.default
        if let data = fm.contents(atPath: dev + "/swiftcode-device-type") {
            let id = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { return id }
        }
        return fm.fileExists(atPath: dev + "/data/var/run/launchd_bootstrap.plist") ? DeviceType.default.id : nil
    }

    func recordedDeviceType() -> String? {
        guard FileManager.default.fileExists(atPath: deviceTypePath) else { return nil }
        return Self.recordedDeviceType(in: dev)
    }

    func checkDeviceType() throws {
        let platform = runtimePlatform()
        if deviceType.platform != platform {
            throw DeviceTypePlatformMismatch(type: deviceType, runtime: platform, runtimeRoot: runtimeRoot)
        }
        let version = runtimeVersion().version
        if !deviceType.runs(onVersion: version), ProcessInfo.processInfo.environment["SWIFTCODE_ALLOW_ANY_DEVICE_TYPE"] != "1" {
            throw DeviceTypeRuntimeMismatch(type: deviceType, runtimeVersion: version, runtimeRoot: runtimeRoot)
        }
        if let recorded = Self.recordedDeviceType(in: dev), recorded != deviceType.id {
            throw DeviceTypeMismatch(what: "the device \(dev)", recorded: recorded, requested: deviceType.id)
        }
    }

    func checkTemplate(_ template: String) throws {
        let recorded = Self.recordedDeviceType(in: template) ?? DeviceType.default.id
        if recorded != deviceType.id {
            throw DeviceTypeMismatch(what: "the golden device \(template)", recorded: recorded, requested: deviceType.id)
        }
        let migration = template + "/data/Library/Preferences/com.apple.migration.plist"
        let build = runtimeVersion().build
        if let data = FileManager.default.contents(atPath: migration),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let last = plist["LastSystemVersion"] as? String, !build.isEmpty, last != build {
            FileHandle.standardError.write(Data("swiftcode-simd: warning: the golden device \(template) was booted on runtime build \(last), not \(build); this boot migrates it\n".utf8))
        }
    }

    func recordMigrationDone() throws {
        let path = data + "/Library/Preferences/com.apple.migration.plist"
        guard !FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        let build = runtimeVersion().build
        try writeXML(["LastSystemVersion": build,
                      "DMLastMigrationResults": ["buildVersion": build, "success": true] as [String: Any],
                      "DMUserDataDisposition": ["buildVersion": build, "EraseIsRapidReturnToService": false,
                                                "SyntheticDidUpgrade": false] as [String: Any]], to: path)
    }

    var loggingSubsystemsPath: String { data + "/Library/Preferences/Logging/Subsystems" }
    var leanLoggingRecordPath: String { dev + "/swiftcode-lean-logging.txt" }

    func applyLoggingPreferences(_ on: Bool) throws {
        let fm = FileManager.default
        let offData = try PropertyListSerialization.data(fromPropertyList: LeanBootProfile.levelOffPreference, format: .xml, options: 0)
        var recorded = (fm.contents(atPath: leanLoggingRecordPath)).map {
            String(decoding: $0, as: UTF8.self).split(separator: "\n").map(String.init)
        } ?? []
        if on {
            try fm.createDirectory(atPath: loggingSubsystemsPath, withIntermediateDirectories: true)
            for subsystem in LeanBootProfile.loggingOffSubsystems where !recorded.contains(subsystem) {
                let path = loggingSubsystemsPath + "/" + subsystem + ".plist"
                guard !fm.fileExists(atPath: path) else { continue }
                try offData.write(to: URL(fileURLWithPath: path))
                recorded.append(subsystem)
            }
        } else {
            for subsystem in recorded {
                let path = loggingSubsystemsPath + "/" + subsystem + ".plist"
                if fm.contents(atPath: path) == offData { try fm.removeItem(atPath: path) }
            }
            recorded = []
        }
        if recorded.isEmpty {
            if fm.fileExists(atPath: leanLoggingRecordPath) { try fm.removeItem(atPath: leanLoggingRecordPath) }
        } else {
            try Data((recorded.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: leanLoggingRecordPath))
        }
    }

    func cloneData(from template: String) throws {
        let source = template + "/data"
        guard FileManager.default.fileExists(atPath: source) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: source])
        }
        try FileManager.default.createDirectory(atPath: dev, withIntermediateDirectories: true)
        #if os(Linux)
        let cp = Process()
        cp.executableURL = URL(fileURLWithPath: "/bin/cp")
        cp.arguments = ["-a", "--reflink=auto", source, data]
        try cp.run()
        cp.waitUntilExit()
        guard cp.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: data])
        }
        #else
        try FileManager.default.copyItem(atPath: source, toPath: data)
        #endif
        FileHandle.standardError.write(Data("swiftcode-simd: device data cloned from \(template)\n".utf8))
    }

    static let audioOutputDeviceUID = "dev.swiftcode.simulator.audio.output"

    private func writeXML(_ plist: [String: Any], to path: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

struct DeviceTypePlatformMismatch: Error, CustomStringConvertible {
    let type: DeviceType
    let runtime: RuntimePlatform
    let runtimeRoot: String
    var description: String {
        let fitting = DeviceType.all.filter { $0.platform == runtime }.map(\.id).joined(separator: ", ")
        return "the device type \(type.id) (\(type.name)) runs on \(type.platform.displayName) runtimes; \(runtimeRoot) is a \(runtime.displayName) runtime (its device types: \(fitting))"
    }
}

struct DeviceTypeRuntimeMismatch: Error, CustomStringConvertible {
    let type: DeviceType
    let runtimeVersion: String
    let runtimeRoot: String
    var description: String {
        let fitting = DeviceType.all.filter { $0.platform == type.platform && $0.runs(onVersion: runtimeVersion) }.map(\.id).joined(separator: ", ")
        return "the device type \(type.id) (\(type.name)) needs runtime \(type.minRuntimeVersion ?? "?") or later; \(runtimeRoot) is \(runtimeVersion) (its device types: \(fitting))"
    }
}

struct DeviceRuntimeDowngrade: Error, CustomStringConvertible {
    let dev: String
    let recorded: DeviceLayout.RuntimeRecord
    let requested: DeviceLayout.RuntimeRecord
    var description: String {
        "the device \(dev) last booted \(recorded.displayName); it cannot boot the older runtime \(requested.displayName) (use another device directory for each runtime)"
    }
}

struct DeviceTypeMismatch: Error, CustomStringConvertible {
    let what: String
    let recorded: String
    let requested: String
    var description: String {
        "\(what) has the device type \(recorded); it cannot boot as \(requested) (use another device directory, or --device-type \(recorded))"
    }
}
