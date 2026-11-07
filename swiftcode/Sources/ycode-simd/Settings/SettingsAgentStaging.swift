import Foundation

extension DeviceLayout {
    static let settingsAgentLabel = "dev.swiftcode.simulator.settings"
    var settingsAgentHostPath: String { data + "/Library/SwiftCode/bin/swiftcode-settings-agent" }
    var settingsAgentPlistPath: String { data + "/Library/LaunchDaemons/\(Self.settingsAgentLabel).plist" }
    var settingsAgentLogPath: String { data + "/tmp/swiftcode-settings-agent.log" }
    var overridesLibraryHostPath: String { data + "/Library/SwiftCode/lib/libSwiftCodeEnvironmentOverrides.dylib" }
    var overridesDirectoryHostPath: String { DeviceSettingsFiles(dev: dev, guestData: guestData).overridesDirectory }

    var settingsAgentPlist: [String: Any] {
        ["Label": Self.settingsAgentLabel,
         "ProgramArguments": [guestPath(settingsAgentHostPath)],
         "RootedSimulatorPath": true,
         "ProcessType": "Interactive",
         "RunAtLoad": true,
         "KeepAlive": true,
         "StandardErrorPath": guestPath(settingsAgentLogPath),
         "EnvironmentVariables": ["SWIFTCODE_SETTINGS_AGENT": "1"]]
    }

    func platformBuild(of source: String) -> String? {
        guard runtimePlatform() != .iOS else { return nil }
        let dir = (source as NSString).deletingLastPathComponent, name = (source as NSString).lastPathComponent
        let variant = dir + "/" + runtimePlatform().rawValue.lowercased() + "/" + name
        return FileManager.default.fileExists(atPath: variant) ? variant : nil
    }

    func stageImage(_ source: String, to target: String, mode: Int) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: target) { try fm.removeItem(atPath: target) }
        let own = platformBuild(of: source)
        try fm.copyItem(atPath: own ?? source, toPath: target)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: target)
        if runtimePlatform() != .iOS, own == nil {
            do {
                try GuestImagePlatform.adapt(fileAt: target, for: runtimePlatform(), version: runtimeVersion().version)
            } catch {
                FileHandle.standardError.write(Data("swiftcode-simd: \((target as NSString).lastPathComponent) is not used on this runtime: \(error)\n".utf8))
                try? fm.removeItem(atPath: target)
                return false
            }
        }
        return true
    }

    func stageSettingsAgent() throws {
        let fm = FileManager.default
        guard let agent = settingsAgent, fm.fileExists(atPath: agent), try stageImage(agent, to: settingsAgentHostPath, mode: 0o755) else {
            if fm.fileExists(atPath: settingsAgentPlistPath) { try fm.removeItem(atPath: settingsAgentPlistPath) }
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: settingsAgentPlist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: settingsAgentPlistPath), options: .atomic)
        if fm.fileExists(atPath: settingsAgentLogPath) { try? fm.removeItem(atPath: settingsAgentLogPath) }
    }

    func stageOverridesLibrary() throws {
        guard let lib = overridesLibrary, FileManager.default.fileExists(atPath: lib) else { return }
        _ = try stageImage(lib, to: overridesLibraryHostPath, mode: 0o755)
        try FileManager.default.createDirectory(atPath: overridesDirectoryHostPath, withIntermediateDirectories: true)
        if let id = launchBundleID {
            try? FileManager.default.removeItem(atPath: DeviceSettingsFiles(dev: dev, guestData: guestData).overridesPath(id))
        }
    }

    var gaugeLibraryHostPath: String { data + "/Library/SwiftCode/lib/libSwiftCodeGauge.dylib" }
    var gaugeSignpostsHostPath: String { data + "/tmp/swiftcode-gauge-signposts.bin" }

    func stageGaugeLibrary() throws {
        guard let lib = gaugeLibrary, FileManager.default.fileExists(atPath: lib) else { return }
        _ = try stageImage(lib, to: gaugeLibraryHostPath, mode: 0o755)
        try? FileManager.default.removeItem(atPath: gaugeSignpostsHostPath)
    }

    var gaugeEnvironment: [String] {
        guard gaugeLibrary != nil else { return [] }
        return ["DYLD_INSERT_LIBRARIES=" + guestPath(gaugeLibraryHostPath), "SWIFTCODE_GAUGE_SIGNPOSTS=/tmp/swiftcode-gauge-signposts.bin"]
    }

    static func mergingInsertedLibraries(_ environment: [String], _ more: [String]) -> [String] {
        let key = "DYLD_INSERT_LIBRARIES="
        let all = environment + more
        let libraries = all.filter { $0.hasPrefix(key) }.map { String($0.dropFirst(key.count)) }.filter { !$0.isEmpty }
        guard libraries.count > 1 else { return all }
        var out: [String] = []
        var placed = false
        for e in all {
            if e.hasPrefix(key) {
                if !placed { out.append(key + libraries.joined(separator: ":")); placed = true }
            } else {
                out.append(e)
            }
        }
        return out
    }

    var overridesEnvironment: [String] {
        guard overridesLibrary != nil else { return [] }
        return ["DYLD_INSERT_LIBRARIES=" + guestPath(overridesLibraryHostPath),
                "SWIFTCODE_ENV_OVERRIDES_DIR=" + DeviceSettingsFiles(dev: dev, guestData: guestData).overridesGuestDirectory]
    }
}
