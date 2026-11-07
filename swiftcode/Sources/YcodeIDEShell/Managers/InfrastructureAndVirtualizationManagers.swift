import Foundation
import Observation
#if canImport(Security)
import Security
#endif

public struct SCDependencyItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let version: String
    public let type: String
    public var status: String
    public let homepage: String
    public let license: String

    public init(id: UUID = UUID(), name: String, version: String, type: String, status: String, homepage: String = "", license: String = "") {
        self.id = id
        self.name = name
        self.version = version
        self.type = type
        self.status = status
        self.homepage = homepage
        self.license = license
    }
}

@Observable
@MainActor
public final class SCOperationsStorageManager {
    public static let shared = SCOperationsStorageManager()

    public var projectUsageGB: Double = 0.0
    public var cacheUsageGB: Double = 0.0
    public var derivedDataGB: Double = 0.0
    public var vmUsageGB: Double = 0.0
    public var archiveUsageGB: Double = 0.0
    public var logUsageGB: Double = 0.0
    public var backupUsageGB: Double = 0.0

    public var totalSystemFreeGB: Double = 0.0

    public var totalAllocatedGB: Double {
        projectUsageGB + cacheUsageGB + derivedDataGB + vmUsageGB + archiveUsageGB + logUsageGB + backupUsageGB
    }

    private init() {
        recalculateSizes()
    }

    public func recalculateSizes() {
        let projectsDir = ProjectSessionStore.shared.projectsDirectory
        let activeProjectDir = ProjectSessionStore.shared.activeProject?.directoryURL
        let archiveBytes = ArchiveManager.shared.archives.reduce(Int64(0)) { $0 + $1.binarySize }
        let vmConfiguredGB = Double(VirtualizationStateStore.shared.virtualMachines.reduce(0) { $0 + $1.storageGB })
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SwiftCode")
        let backupsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SwiftCode/Backups")

        Task.detached(priority: .background) {
            let projectsBytes = SCOperationsStorageManager.getDirectorySize(at: projectsDir)
            let projectUsage = Double(projectsBytes) / (1024 * 1024 * 1024)

            var derivedUsage = 0.0
            if let activeDir = activeProjectDir {
                let derivedURL = activeDir.appendingPathComponent("build")
                let derivedBytes = SCOperationsStorageManager.getDirectorySize(at: derivedURL)
                derivedUsage = Double(derivedBytes) / (1024 * 1024 * 1024)
            }

            let cachesBytes = SCOperationsStorageManager.getDirectorySize(at: cachesDir)
            let backupsBytes = SCOperationsStorageManager.getDirectorySize(at: backupsDir)

            var freeGB = 0.0
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
                if let freeSpace = attrs[.systemFreeSize] as? Int64 {
                    freeGB = Double(freeSpace) / (1024 * 1024 * 1024)
                }
            }

            let cacheUsage = Double(cachesBytes) / (1024 * 1024 * 1024)
            let backupUsage = Double(backupsBytes) / (1024 * 1024 * 1024)
            let archiveUsage = Double(archiveBytes) / (1024 * 1024 * 1024)

            await MainActor.run {
                self.projectUsageGB = projectUsage
                self.derivedDataGB = derivedUsage
                self.cacheUsageGB = cacheUsage
                self.vmUsageGB = vmConfiguredGB
                self.archiveUsageGB = archiveUsage
                self.logUsageGB = 0.0
                self.backupUsageGB = backupUsage
                self.totalSystemFreeGB = freeGB
                WorkspaceHealth.shared.recompute()
            }
        }
    }

    nonisolated private static func getDirectorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var size: Int64 = 0
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else { return 0 }
        while let fileURL = enumerator.nextObject() as? URL {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }

    public func cleanDerivedData() {
        if let project = ProjectSessionStore.shared.activeProject {
            let buildDir = project.directoryURL.appendingPathComponent("build")
            try? FileManager.default.removeItem(at: buildDir)
            recalculateSizes()
        }
    }

    public func cleanCaches() {
        let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SwiftCode")
        try? FileManager.default.removeItem(at: cachesURL)
        recalculateSizes()
    }
}

@Observable
@MainActor
public final class DependencyManager {
    public static let shared = DependencyManager()

    public var dependencies: [SCDependencyItem] = []

    private init() {
        refreshDependencies()
    }

    public func refreshDependencies() {
        dependencies.removeAll()

        guard let project = ProjectSessionStore.shared.activeProject else { return }

        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packageURL.path),
              let contents = try? String(contentsOf: packageURL, encoding: .utf8),
              contents.contains(".package") else { return }

        let resolved = Self.resolvedVersions(in: project.directoryURL)

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(".package(") else { continue }
            if let url = Self.quotedValue(after: "url:", in: trimmed) {
                let name = url.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "Package"
                dependencies.append(SCDependencyItem(
                    name: name,
                    version: resolved[name.lowercased()] ?? "Unknown",
                    type: "Swift Package",
                    status: "Unknown",
                    homepage: url,
                    license: ""
                ))
            } else if let path = Self.quotedValue(after: "path:", in: trimmed) {
                let name = path.components(separatedBy: "/").last ?? "Package"
                dependencies.append(SCDependencyItem(
                    name: name,
                    version: "Unknown",
                    type: "Local Package",
                    status: "Unknown",
                    homepage: "",
                    license: ""
                ))
            }
        }
    }

    private static func quotedValue(after label: String, in line: String) -> String? {
        guard let labelRange = line.range(of: label) else { return nil }
        let rest = line[labelRange.upperBound...]
        guard let open = rest.firstIndex(of: "\""),
              let close = rest[rest.index(after: open)...].firstIndex(of: "\"") else { return nil }
        return String(rest[rest.index(after: open)..<close])
    }

    private static func resolvedVersions(in directory: URL) -> [String: String] {
        let resolvedURL = directory.appendingPathComponent("Package.resolved")
        guard let data = try? Data(contentsOf: resolvedURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        let pins = (root["pins"] as? [[String: Any]])
            ?? (root["object"] as? [String: Any])?["pins"] as? [[String: Any]]
            ?? []
        var out: [String: String] = [:]
        for pin in pins {
            guard let state = pin["state"] as? [String: Any],
                  let version = state["version"] as? String, !version.isEmpty else { continue }
            if let identity = pin["identity"] as? String, !identity.isEmpty {
                out[identity.lowercased()] = version
            }
            if let name = pin["package"] as? String, !name.isEmpty {
                out[name.lowercased()] = version
            }
            var remotes: [String] = []
            if let location = pin["location"] as? String { remotes.append(location) }
            if let location = pin["location"] as? [String: Any],
               let array = location["remote"] as? [String] { remotes += array }
            if let repositoryURL = pin["repositoryURL"] as? String { remotes.append(repositoryURL) }
            for url in remotes {
                if let repo = url.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: ""), !repo.isEmpty {
                    out[repo.lowercased()] = version
                }
            }
        }
        return out
    }
}

public struct SCDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let platform: String
    public let osVersion: String
    public var status: String

    public init(id: String, name: String, model: String, platform: String, osVersion: String, status: String) {
        self.id = id
        self.name = name
        self.model = model
        self.platform = platform
        self.osVersion = osVersion
        self.status = status
    }
}

@Observable
@MainActor
public final class SCOperationsDeviceManager {
    public static let shared = SCOperationsDeviceManager()

    public var devices: [SCDevice] = []

    private init() {
        refreshDevices()
    }

    public func refreshDevices() {
        var found: [SCDevice] = []

        #if os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let model = Self.runCommand("/usr/sbin/sysctl", ["-n", "hw.model"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        found.append(SCDevice(
            id: "MAC-SELF",
            name: hostName,
            model: (model?.isEmpty == false) ? model! : "Mac",
            platform: "macOS",
            osVersion: osVersion,
            status: "Connected"))
        #endif

        found += Self.physicalDevices()
        found += Self.simulatorDevices()
        self.devices = found
    }

    private static func physicalDevices() -> [SCDevice] {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftcode-devicectl-\(ProcessInfo.processInfo.processIdentifier).json")
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard runCommand("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", scratch.path, "-q"]) != nil,
              let data = try? Data(contentsOf: scratch),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let list = result["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { device in
            let hw = device["hardwareProperties"] as? [String: Any] ?? [:]
            let props = device["deviceProperties"] as? [String: Any] ?? [:]
            guard (hw["reality"] as? String) == "physical",
                  let platform = hw["platform"] as? String,
                  let udid = hw["udid"] as? String,
                  let name = props["name"] as? String else { return nil }
            let model = (hw["model"] as? String) ?? (hw["deviceType"] as? String) ?? platform
            return SCDevice(
                id: udid,
                name: name,
                model: model,
                platform: platform,
                osVersion: (props["osVersionNumber"] as? String) ?? "",
                status: "Connected")
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func simulatorDevices() -> [SCDevice] {
        guard let data = runCommandData("/usr/bin/xcrun", ["simctl", "list", "-j", "devices"]),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return [] }
        let runtimePlatforms = ["iOS": "iOS", "watchOS": "watchOS", "tvOS": "tvOS", "xrOS": "visionOS", "visionOS": "visionOS"]
        var out: [SCDevice] = []
        for (runtime, devices) in byRuntime {
            let tail = runtime.split(separator: ".").last.map(String.init) ?? runtime
            let parts = tail.split(separator: "-").map(String.init)
            guard let first = parts.first, let platform = runtimePlatforms[first] else { continue }
            let version = parts.dropFirst().joined(separator: ".")
            for device in devices where (device["isAvailable"] as? Bool) ?? true {
                guard let name = device["name"] as? String,
                      let udid = device["udid"] as? String else { continue }
                let model = (device["deviceTypeIdentifier"] as? String)?
                    .replacingOccurrences(of: "com.apple.CoreSimulator.SimDeviceType.", with: "")
                    .replacingOccurrences(of: "-", with: " ") ?? name
                let state = (device["state"] as? String) ?? ""
                out.append(SCDevice(
                    id: udid,
                    name: name,
                    model: model,
                    platform: platform,
                    osVersion: version,
                    status: state == "Booted" ? "Connected" : "Offline"))
            }
        }
        return out.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) -> String? {
        guard let data = runCommandData(executable, arguments) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func runCommandData(_ executable: String, _ arguments: [String]) -> Data? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return data
    }
}

public struct SCSigningCertificate: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let type: String
    public let expirationDate: Date
    public var isValid: Bool

    public init(id: String, name: String, type: String, expirationDate: Date, isValid: Bool = true) {
        self.id = id
        self.name = name
        self.type = type
        self.expirationDate = expirationDate
        self.isValid = isValid
    }
}

@Observable
@MainActor
public final class SCOperationsSigningManager {
    public static let shared = SCOperationsSigningManager()

    public var certificates: [SCSigningCertificate] = []

    private init() {
        refreshCertificates()
    }

    public func refreshCertificates() {
        self.certificates = Self.loadSigningCertificates()
    }

    private static func loadSigningCertificates() -> [SCSigningCertificate] {
        guard let output = runFindIdentity() else { return [] }
        let identities = parseFindIdentity(output)
        guard !identities.isEmpty else { return [] }
        let expiries = certificateExpiriesByName()
        let now = Date()
        return identities.compactMap { identity in
            guard let expiry = expiries[identity.name] else { return nil }
            return SCSigningCertificate(
                id: "CERT-\(identity.hash)",
                name: identity.name,
                type: certificateType(for: identity.name),
                expirationDate: expiry,
                isValid: expiry > now
            )
        }
    }

    private static func runFindIdentity() -> String? {
        let security = "/usr/bin/security"
        guard FileManager.default.isExecutableFile(atPath: security) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: security)
        process.arguments = ["find-identity", "-v", "-p", "codesigning"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func parseFindIdentity(_ text: String) -> [(hash: String, name: String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let paren = t.firstIndex(of: ")"), Int(t[..<paren]) != nil else { continue }
            let rest = t[t.index(after: paren)...].trimmingCharacters(in: .whitespaces)
            guard let space = rest.firstIndex(of: " ") else { continue }
            let hash = String(rest[..<space])
            var name = rest[space...].trimmingCharacters(in: .whitespaces)
            guard hash.count == 40, hash.allSatisfy(\.isHexDigit), name.hasPrefix("\"") else { continue }
            name.removeFirst()
            guard let close = name.lastIndex(of: "\"") else { continue }
            if seen.insert(hash.uppercased()).inserted {
                out.append((hash.uppercased(), String(name[..<close])))
            }
        }
        return out
    }

    private static func certificateExpiriesByName() -> [String: Date] {
#if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let certs = out as? [SecCertificate] else { return [:] }
        var map: [String: Date] = [:]
        for cert in certs {
            guard let summary = SecCertificateCopySubjectSummary(cert) as String?,
                  let expiry = SecCertificateCopyNotValidAfter(cert) as Date? else { continue }
            map[summary] = expiry
        }
        return map
#else
        return [:]
#endif
    }

    private static func certificateType(for name: String) -> String {
        if name.hasPrefix("Apple Development") || name.hasPrefix("iPhone Developer") || name.hasPrefix("Mac Developer") {
            return "Development"
        }
        if name.hasPrefix("Apple Distribution") || name.hasPrefix("iPhone Distribution")
            || name.hasPrefix("Developer ID") || name.contains("Distribution") {
            return "Distribution"
        }
        if let colon = name.firstIndex(of: ":") {
            return String(name[..<colon])
        }
        return name
    }
}

public struct SCVirtualMachine: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let os: String
    public let ramMB: Int
    public let cores: Int
    public var status: String
    public var uptime: TimeInterval
    public var storageGB: Int
    public var ipAddress: String?
    public var snapshotCount: Int
    public var attachedProjectsCount: Int

    public init(id: UUID = UUID(), name: String, os: String, ramMB: Int, cores: Int, status: String, uptime: TimeInterval = 0, storageGB: Int = 20, ipAddress: String? = nil, snapshotCount: Int = 0, attachedProjectsCount: Int = 0) {
        self.id = id
        self.name = name
        self.os = os
        self.ramMB = ramMB
        self.cores = cores
        self.status = status
        self.uptime = uptime
        self.storageGB = storageGB
        self.ipAddress = ipAddress
        self.snapshotCount = snapshotCount
        self.attachedProjectsCount = attachedProjectsCount
    }
}

@Observable
@MainActor
public final class VirtualizationIntegration {
    public static let shared = VirtualizationIntegration()

    public var virtualMachines: [SCVirtualMachine] = []

    private init() {
        refreshVMs()
    }

    public func refreshVMs() {
        let storeVMs = VirtualizationStateStore.shared.virtualMachines
        self.virtualMachines = storeVMs.map { vm in
            SCVirtualMachine(
                id: vm.id,
                name: vm.name,
                os: vm.osType,
                ramMB: vm.memoryMB,
                cores: vm.cpuCores,
                status: vm.status.rawValue,
                uptime: vm.uptime,
                storageGB: vm.storageGB,
                ipAddress: vm.ipAddress,
                snapshotCount: vm.snapshots.count,
                attachedProjectsCount: vm.attachedProjects.count
            )
        }
    }
}

@Observable
@MainActor
public final class BackupIntegration {
    public static let shared = BackupIntegration()

    public var backups: [SCBackup] = []

    private init() {
        refreshBackups()
    }

    public func refreshBackups() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backupsDir = appSupport.appendingPathComponent("SwiftCode/Backups")

        if let contents = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            self.backups = contents.map { url in
                SCBackup(
                    projectName: url.deletingPathExtension().lastPathComponent,
                    date: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date(),
                    size: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
                    path: url.path
                )
            }
        } else {
            self.backups = []
        }
    }

    public func createBackup(for project: SCProjectRegistryEntry) {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backupsDir = appSupport.appendingPathComponent("SwiftCode/Backups")

        try? fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)

        let backupName = "\(project.name)_\(Int(Date().timeIntervalSince1970)).zip"
        let backupURL = backupsDir.appendingPathComponent(backupName)

        let zipContent = "SwiftCode Archive of \(project.name)"
        try? zipContent.write(to: backupURL, atomically: true, encoding: .utf8)

        refreshBackups()
        SCOperationsStorageManager.shared.recalculateSizes()
    }
}

@Observable
@MainActor
public final class CloudIntegration {
    public static let shared = CloudIntegration()

    public var isConnected: Bool = false
    public var cloudUser: String? = nil
    public var storageQuotaUsedGB: Double? = nil
    public var storageQuotaMaxGB: Double? = nil

    private init() {
        refreshCloudStatus()
    }

    public func refreshCloudStatus() {
        if AuthManager.shared.isAuthenticated {
            self.isConnected = true
            self.cloudUser = AuthManager.shared.currentUser?.email ?? "Developer"
            self.storageQuotaUsedGB = nil
            self.storageQuotaMaxGB = nil
        } else {
            self.isConnected = false
            self.cloudUser = nil
            self.storageQuotaUsedGB = nil
            self.storageQuotaMaxGB = nil
        }
    }
}
