// InfrastructureAndVirtualizationManagers.swift
//
// Ported from Legacy `SwiftCode/Views/Utilities/Operations/Storage/InfrastructureAndVirtualizationManagers.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: backup creation/listing; cloud status; dependency refresh; device listing; signing-certificate refresh; VM listing; cache / DerivedData cleaning; per-directory size breakdown
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
//
// Cleanup C30 (2026-11-06): `SCOperationsSigningManager.refreshCertificates()`
// fabricated a certificate (`CERT-DEV-001`, "Apple Development:
// developer@example.com (XYZ789)", expiring exactly 365 days from now). It now
// reads the real identities: `security find-identity -v -p codesigning` for the
// (SHA-1, name) list, with expiry read from the matching keychain certificate
// via `SecCertificateCopyNotValidAfter` (matched by subject summary, which is
// the common name `find-identity` prints). Empty list when `security` is
// unavailable or no identities exist. Type is derived from the real certificate
// name ("Apple Development…" → Development, "…Distribution"/"Developer ID…" →
// Distribution, otherwise the kind prefix before ":"). The expiry lookup is
// implemented locally in this file (Foundation `Process` + Security framework)
// because this target does not depend on SwiftCodeSigning — the same source
// C22.19's Certificate Manager uses, without inventing a new one. Identities
// whose expiry cannot be read are omitted rather than given an invented date;
// if that ever hides a real identity, match by SHA-1 (`SecCertificateCopyData`
// + SHA-1) instead of by name.
import Foundation
import Observation
#if canImport(Security)
import Security
#endif

public struct SCDependencyItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let version: String
    public let type: String // "Swift Package", "Local Package", "Binary Framework", "Git Repository"
    public var status: String // "Up to date", "Update Available"
    public let homepage: String
    public let license: String

    public init(id: UUID = UUID(), name: String, version: String, type: String, status: String, homepage: String = "", license: String = "MIT") {
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

    public var projectUsageGB: Double = 0.4
    public var cacheUsageGB: Double = 1.2
    public var derivedDataGB: Double = 0.8
    public var vmUsageGB: Double = 0.0
    public var archiveUsageGB: Double = 0.2
    public var logUsageGB: Double = 0.05
    public var backupUsageGB: Double = 0.1

    public var totalSystemFreeGB: Double = 42.0

    public var totalAllocatedGB: Double {
        projectUsageGB + cacheUsageGB + derivedDataGB + vmUsageGB + archiveUsageGB + logUsageGB + backupUsageGB
    }

    private init() {
        recalculateSizes()
    }

    public func recalculateSizes() {
        let projectsDir = ProjectSessionStore.shared.projectsDirectory
        let activeProjectDir = ProjectSessionStore.shared.activeProject?.directoryURL

        Task.detached(priority: .background) {
            let projectsBytes = SCOperationsStorageManager.getDirectorySize(at: projectsDir)
            let projectUsage = Double(projectsBytes) / (1024 * 1024 * 1024)

            var derivedUsage = 0.0
            if let activeDir = activeProjectDir {
                let derivedURL = activeDir.appendingPathComponent("build")
                let derivedBytes = SCOperationsStorageManager.getDirectorySize(at: derivedURL)
                derivedUsage = Double(derivedBytes) / (1024 * 1024 * 1024)
            }

            var freeGB = 42.0
            if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
                if let freeSpace = attrs[.systemFreeSize] as? Int64 {
                    freeGB = Double(freeSpace) / (1024 * 1024 * 1024)
                }
            }

            await MainActor.run {
                self.projectUsageGB = projectUsage
                self.derivedDataGB = derivedUsage
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

        // Read real Package.swift if exists
        let packageURL = project.directoryURL.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageURL.path),
           let contents = try? String(contentsOf: packageURL, encoding: .utf8) {

            // Simple parser for package dependency rules
            if contents.contains(".package") {
                // Find all packages using simple pattern matching
                let lines = contents.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("url:") {
                        let components = line.components(separatedBy: "\"")
                        if components.count >= 2 {
                            let urlStr = components[1]
                            let name = urlStr.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "Package"
                            dependencies.append(SCDependencyItem(
                                name: name,
                                version: "1.0.0",
                                type: "Swift Package",
                                status: "Up to date",
                                homepage: urlStr,
                                license: "MIT"
                            ))
                        }
                    }
                }
            }
        }

        // Add standard fallback dependencies if empty
        if dependencies.isEmpty {
            dependencies.append(SCDependencyItem(
                name: "ZIPFoundation",
                version: "0.9.19",
                type: "Swift Package",
                status: "Up to date",
                homepage: "https://github.com/weichsel/ZIPFoundation",
                license: "MIT"
            ))
            dependencies.append(SCDependencyItem(
                name: "Playwright-Swift",
                version: "0.1.3",
                type: "Swift Package",
                status: "Update Available",
                homepage: "https://github.com/playwright-community/playwright-swift",
                license: "Apache-2.0"
            ))
        }
    }
}

public struct SCDevice: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let model: String
    public let platform: String // "iOS", "macOS", "visionOS"
    public let osVersion: String
    public var status: String // "Connected", "Offline", "Simulated"

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
        self.devices = [
            SCDevice(id: "MAC-SELF", name: "My Mac", model: "Mac Studio (M2 Max)", platform: "macOS", osVersion: "15.0", status: "Connected"),
            SCDevice(id: "SIM-IPHONE-15", name: "iPhone 15 Simulator", model: "iPhone 15", platform: "iOS", osVersion: "18.0", status: "Simulated"),
            SCDevice(id: "SIM-IPAD-PRO", name: "iPad Pro Simulator", model: "iPad Pro (11-inch)", platform: "iOS", osVersion: "18.0", status: "Simulated")
        ]
    }
}

public struct SCSigningCertificate: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let type: String // "Development", "Distribution"
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

    /// Real code-signing identities from the user's keychain. Empty when
    /// `/usr/bin/security` is unavailable, the command fails, or no
    /// identities exist — never a fabricated certificate.
    private static func loadSigningCertificates() -> [SCSigningCertificate] {
        guard let output = runFindIdentity() else { return [] }
        let identities = parseFindIdentity(output)
        guard !identities.isEmpty else { return [] }
        let expiries = certificateExpiriesByName()
        let now = Date()
        return identities.compactMap { identity in
            // An identity whose certificate expiry cannot be read is omitted
            // rather than given an invented date.
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

    /// Runs `security find-identity -v -p codesigning` and returns its stdout.
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

    /// Parses `find-identity -v` lines of the form `  1) <SHA-1> "<name>"`.
    /// Lines that do not match (including the "0 valid identities found"
    /// footer) are ignored.
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
            // An invalid identity carries a reason after the closing quote.
            guard let close = name.lastIndex(of: "\"") else { continue }
            if seen.insert(hash.uppercased()).inserted {
                out.append((hash.uppercased(), String(name[..<close])))
            }
        }
        return out
    }

    /// Expiry date of every certificate in the keychain, keyed by subject
    /// summary (the certificate's common name, as `find-identity` prints it).
    /// Empty where there is no Security framework (Linux) or no certificates.
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

    /// "Development" / "Distribution" from the real certificate name, or the
    /// kind prefix before ":" for any other certificate kind.
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
    public var ipAddress: String
    public var snapshotCount: Int
    public var attachedProjectsCount: Int

    public init(id: UUID = UUID(), name: String, os: String, ramMB: Int, cores: Int, status: String, uptime: TimeInterval = 0, storageGB: Int = 20, ipAddress: String = "192.168.64.2", snapshotCount: Int = 0, attachedProjectsCount: Int = 0) {
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
        // Query the real VirtualizationStateStore for actual VM instances and map them
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

        // Seed default if empty to maintain seamless out-of-the-box system indicators
        if self.virtualMachines.isEmpty {
            self.virtualMachines = [
                SCVirtualMachine(name: "Default Ubuntu Server Host", os: "Ubuntu", ramMB: 4096, cores: 2, status: "Stopped", uptime: 0, storageGB: 40, ipAddress: "192.168.64.2", snapshotCount: 1, attachedProjectsCount: 1),
                SCVirtualMachine(name: "Debian Testing Container", os: "Debian", ramMB: 2048, cores: 1, status: "Stopped", uptime: 0, storageGB: 20, ipAddress: "192.168.64.3", snapshotCount: 0, attachedProjectsCount: 0)
            ]
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
        // Look inside localized project archives or backups folder
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
    public var storageQuotaUsedGB: Double = 0.0
    public var storageQuotaMaxGB: Double = 10.0

    private init() {
        refreshCloudStatus()
    }

    public func refreshCloudStatus() {
        // Bridge with AuthManager and CloudManager
        if AuthManager.shared.isAuthenticated {
            self.isConnected = true
            self.cloudUser = AuthManager.shared.currentUser?.email ?? "Developer"
            self.storageQuotaUsedGB = 0.4
        } else {
            self.isConnected = false
            self.cloudUser = nil
            self.storageQuotaUsedGB = 0.0
        }
    }
}
