import Foundation
import Crypto
import YcodeExtensions

// MARK: - SDKInstalledExtension
//
// Ported from Legacy `SwiftCode/SDK/Host/ExtensionRegistry/SDKExtensionRegistry.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The SDK host's registry for `swiftcode.json` packages. This is a
// SEPARATE registry from the v2 VS Code extension manager
// (`ExtensionsV2/`): it tracks SDK packages by id/version under
// `Extensions/<id>/<version>/`, re-validates the manifest on every
// scan, and binds each install to a canonical SHA-256 package digest.
//
// Digest: CryptoKit in Legacy, swift-crypto `Crypto` here — the same
// incremental SHA-256 API. Manifest validation delegates to
// YcodeExtensions' `SwiftCodeManifestValidator` (the strict validator,
// spec §2.3), never a second validator.

public struct SDKInstalledExtension: Sendable {
    public let id: String
    public let name: String
    public let version: String
    /// Canonical SHA-256 hex digest of the installed tree.
    public let packageDigest: String
    public let installPath: URL
    public let installedAt: Date
    public let updatedAt: Date
    public let enabled: Bool
    public let manifest: SwiftCodeManifest

    public init(id: String, name: String, version: String, packageDigest: String, installPath: URL, installedAt: Date, updatedAt: Date, enabled: Bool, manifest: SwiftCodeManifest) {
        self.id = id
        self.name = name
        self.version = version
        self.packageDigest = packageDigest
        self.installPath = installPath
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.enabled = enabled
        self.manifest = manifest
    }
}

/// Host metadata record (`.sdk-install.json`). Carries no manifest —
/// the manifest is re-read and re-validated from `swiftcode.json` on
/// every scan, so a tampered manifest fails closed here.
private struct SDKInstallRecord: Codable {
    var id: String
    var name: String
    var version: String
    var packageDigest: String
    var installedAt: Date
    var updatedAt: Date
    var enabled: Bool

    init(from ext: SDKInstalledExtension) {
        id = ext.id
        name = ext.name
        version = ext.version
        packageDigest = ext.packageDigest
        installedAt = ext.installedAt
        updatedAt = ext.updatedAt
        enabled = ext.enabled
    }

    func installedExtension(with manifest: SwiftCodeManifest, installPath: URL) -> SDKInstalledExtension {
        SDKInstalledExtension(
            id: id, name: name, version: version, packageDigest: packageDigest,
            installPath: installPath, installedAt: installedAt, updatedAt: updatedAt,
            enabled: enabled, manifest: manifest
        )
    }
}

public actor SDKExtensionRegistry {
    public static let shared = SDKExtensionRegistry()

    public static let metadataFileName = ".sdk-install.json"
    public static let manifestFileName = "swiftcode.json"

    /// Files excluded from the package digest.
    public static let digestExcludedNames: Set<String> = [".sdk-install.json"]

    /// Chunk size for streaming file contents into the digest.
    public static let digestChunkSize = 10 * 1024 * 1024

    public static var extensionsRoot: URL {
        #if os(macOS)
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("SwiftCode/Extensions", isDirectory: true)
        #else
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config", isDirectory: true)
        return base.appendingPathComponent("ycode/sdk-extensions", isDirectory: true)
        #endif
    }

    private var cache: [String: SDKInstalledExtension] = [:]

    private init() {}

    // MARK: - Scan

    /// Re-scans the extensions root. Every version directory is
    /// re-validated: the manifest must parse under the strict validator
    /// and its id/version must match the directory layout. Malformed
    /// entries are skipped and logged, never fatal. When several
    /// versions of an id are installed, the newest (semver-aware) wins.
    public func scan() async {
        cache = [:]
        guard let idNames = try? FileManager.default.contentsOfDirectory(atPath: Self.extensionsRoot.path) else {
            return
        }
        for id in idNames.sorted() {
            let idDir = Self.extensionsRoot.appendingPathComponent(id, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: idDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            var best: SDKInstalledExtension?
            for version in versionDirectories(in: idDir) {
                let versionDir = idDir.appendingPathComponent(version, isDirectory: true)
                guard let ext = readInstall(id: id, version: version, at: versionDir) else { continue }
                if let current = best, compareVersions(current.version, ext.version) >= 0 { continue }
                best = ext
            }
            if let best { cache[id] = best }
        }
    }

    public func installedExtension(id: String) -> SDKInstalledExtension? {
        cache[id]
    }

    public func installedExtensions() -> [SDKInstalledExtension] {
        cache.values.sorted { $0.id < $1.id }
    }

    // MARK: - Digest

    /// Canonical SHA-256 digest of the installed tree at `url`.
    /// Entries are sorted by relative path; each contributes
    /// `relativePath + NUL + kindByte + NUL + content`, where the kind
    /// byte is `d` (directory), `f` (file), or `l` (symlink). File
    /// contents stream in 10 MB chunks; symlinks contribute their
    /// target; directories contribute nothing. `.sdk-install.json` is
    /// excluded. The digest is stable across machines for identical trees.
    public func computeDigest(of url: URL) throws -> String {
        var hasher = SHA256()
        let rootPath = url.standardizedFileURL.path
        var entries: [(relative: String, url: URL, kind: UInt8, isSymlink: Bool)] = []
        try collectEntries(at: url, rootPath: rootPath, into: &entries)
        entries.sort { $0.relative < $1.relative }
        for entry in entries {
            hasher.update(data: Data(entry.relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data([entry.kind]))
            hasher.update(data: Data([0]))
            if entry.isSymlink {
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: entry.url.path)) ?? ""
                hasher.update(data: Data(target.utf8))
            } else if entry.kind == UInt8(ascii: "f") {
                try hashFileContents(at: entry.url, into: &hasher)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func collectEntries(
        at url: URL,
        rootPath: String,
        into entries: inout [(relative: String, url: URL, kind: UInt8, isSymlink: Bool)]
    ) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
        for name in names {
            if Self.digestExcludedNames.contains(name) { continue }
            let child = url.appendingPathComponent(name)
            let relative = Self.relativePath(of: child, to: rootPath)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: child.path)) != nil {
                entries.append((relative, child, UInt8(ascii: "l"), true))
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                entries.append((relative, child, UInt8(ascii: "d"), false))
                try collectEntries(at: child, rootPath: rootPath, into: &entries)
            } else {
                entries.append((relative, child, UInt8(ascii: "f"), false))
            }
        }
    }

    private func hashFileContents(at url: URL, into hasher: inout SHA256) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw registryError(
                code: .packageIntegrityFailure,
                message: "Could not read a file while computing the package digest.",
                diagnostics: ["path": url.lastPathComponent]
            )
        }
        defer { try? handle.close() }
        while true {
            let chunk = try handle.read(upToCount: Self.digestChunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
    }

    // MARK: - Record install

    /// Writes the install record for `ext` (atomic temp+replace, 0600,
    /// sorted keys). Keeps the in-memory cache consistent: only a newer
    /// version replaces a cached entry.
    public func recordInstall(_ ext: SDKInstalledExtension) throws {
        try ensureExtensionsRoot()
        let versionDir = versionDirectory(id: ext.id, version: ext.version)
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        let record = SDKInstallRecord(from: ext)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw registryError(
                code: .installFailed,
                message: "Could not encode the install record.",
                suggestion: "Try the installation again.",
                diagnostics: ["encodeError": String(describing: error)]
            )
        }

        let recordURL = versionDir.appendingPathComponent(Self.metadataFileName, isDirectory: false)
        do {
            // Atomic write so a crash mid-write never leaves a half record.
            let temporaryURL = versionDir.appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            if FileManager.default.fileExists(atPath: recordURL.path) {
                _ = try FileManager.default.replaceItem(at: recordURL, withItemAt: temporaryURL, backupItemName: nil, options: [], resultingItemURL: nil)
            } else {
                try FileManager.default.moveItem(at: temporaryURL, to: recordURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: recordURL.path)
            }
        } catch {
            throw registryError(
                code: .installFailed,
                message: "Could not write the install record.",
                suggestion: "Check the extensions directory permissions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }

        // Keep the in-memory cache consistent.
        if let existing = cache[ext.id], compareVersions(existing.version, ext.version) >= 0 {
            return
        }
        cache[ext.id] = ext
    }

    // MARK: - Enable / disable

    /// Flips the `enabled` flag in the `.sdk-install.json` metadata for the
    /// extension (all installed versions). Used by the disable/enable flows;
    /// the runtime coordinator performs the actual deactivation separately.
    /// The `updatedAt` timestamp is left untouched — a flag flip is not an
    /// update of the installed tree.
    public func setEnabled(_ enabled: Bool, extensionID: String) throws {
        try ensureExtensionsRoot()
        let idDir = Self.extensionsRoot.appendingPathComponent(extensionID, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: idDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw registryError(
                code: .installFailed,
                message: "The extension is not installed.",
                suggestion: "Install the extension before enabling or disabling it.",
                diagnostics: ["extensionID": extensionID]
            )
        }

        var touched = 0
        for versionName in versionDirectories(in: idDir) {
            let versionDir = idDir.appendingPathComponent(versionName, isDirectory: true)
            let recordURL = versionDir.appendingPathComponent(Self.metadataFileName, isDirectory: false)
            guard let record = readRecord(at: recordURL), record.id == extensionID else { continue }
            var updated = record
            updated.enabled = enabled
            try writeRecord(updated, to: recordURL)
            touched += 1
            if var cached = cache[extensionID], cached.version == record.version {
                cached = SDKInstalledExtension(
                    id: cached.id, name: cached.name, version: cached.version,
                    packageDigest: cached.packageDigest, installPath: cached.installPath,
                    installedAt: cached.installedAt, updatedAt: cached.updatedAt,
                    enabled: enabled, manifest: cached.manifest
                )
                cache[extensionID] = cached
            }
        }

        guard touched > 0 else {
            throw registryError(
                code: .installFailed,
                message: "The extension has no install record to update.",
                suggestion: "Reinstall the extension and try again.",
                diagnostics: ["extensionID": extensionID]
            )
        }
    }

    // MARK: - Remove install record

    /// Deletes the `<root>/<extensionID>/<version>/` directory tree.
    /// Called by the uninstall flow AFTER the extension has been deactivated.
    /// Removes the now-empty parent id directory when no versions remain,
    /// and drops the id from the in-memory cache.
    ///
    /// The extension's Security namespace is wiped FIRST: every Keychain
    /// item the extension stored via `use.Security` (all app Security IDs,
    /// all value IDs) is deleted before the install record goes away. The
    /// wipe is fail-closed — a Keychain failure aborts the uninstall with
    /// `.uninstallFailed` so secrets can never silently survive an
    /// uninstall that reported success. Revoking grants is the Studio
    /// uninstall view's job (it calls `PermissionManager.revokeAll(for:)`
    /// next); stored values are deleted here regardless of grant state.
    public func removeInstallRecord(extensionID: String, version: String) async throws {
        do {
            try await SDKSecurityService.shared.deleteAllValues(securityID: extensionID)
        } catch {
            let underlying = (error as? SDKError)?.code.rawValue ?? "unknown"
            throw registryError(
                code: .uninstallFailed,
                message: "Could not delete the extension's stored secrets.",
                suggestion: "Check that the macOS Keychain is unlocked and try again.",
                diagnostics: ["extensionID": extensionID, "underlyingCode": underlying]
            )
        }

        let versionDir = versionDirectory(id: extensionID, version: version)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: versionDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw registryError(
                code: .uninstallFailed,
                message: "The extension version is not installed.",
                suggestion: "The requested extension version is already gone.",
                diagnostics: ["extensionID": extensionID, "version": version]
            )
        }
        do {
            try FileManager.default.removeItem(at: versionDir)
        } catch {
            throw registryError(
                code: .uninstallFailed,
                message: "Could not remove the installed extension.",
                suggestion: "Check the extensions directory permissions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }

        // Drop the empty parent id directory.
        let idDir = versionDir.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: idDir.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: idDir)
        }

        if let cached = cache[extensionID], cached.version == version {
            cache.removeValue(forKey: extensionID)
        }
    }

    // MARK: - Reading one install

    /// Reads and validates a single installed version directory. Returns
    /// `nil` for anything malformed (logged), never throws — the scan must
    /// not fail on one bad entry.
    private func readInstall(id: String, version: String, at versionDir: URL) -> SDKInstalledExtension? {
        // 1. Host metadata record.
        let recordURL = versionDir.appendingPathComponent(Self.metadataFileName, isDirectory: false)
        guard let record = readRecord(at: recordURL) else {
            SDKLog.error("Skipping install \(id)/\(version): missing or unreadable .sdk-install.json",
                         subsystem: "com.swiftcode.sdk", category: "sdk-registry")
            return nil
        }
        guard record.id == id, record.version == version else {
            SDKLog.error("Skipping install \(id)/\(version): record identity does not match directory layout",
                         subsystem: "com.swiftcode.sdk", category: "sdk-registry")
            return nil
        }

        // 2. Manifest: re-read AND re-validate. A tampered swiftcode.json
        //    fails closed here — the record alone is never trusted.
        let manifestURL = versionDir.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            SDKLog.error("Skipping install \(id)/\(version): swiftcode.json unreadable",
                         subsystem: "com.swiftcode.sdk", category: "sdk-registry")
            return nil
        }
        let manifest: SwiftCodeManifest
        do {
            manifest = try SwiftCodeManifestValidator.validate(data: manifestData)
        } catch {
            SDKLog.error("Skipping install \(id)/\(version): manifest re-validation failed: \(String(describing: error))",
                         subsystem: "com.swiftcode.sdk", category: "sdk-registry")
            return nil
        }
        guard manifest.id == id, manifest.version == version else {
            SDKLog.error("Skipping install \(id)/\(version): manifest identity does not match directory layout",
                         subsystem: "com.swiftcode.sdk", category: "sdk-registry")
            return nil
        }

        return record.installedExtension(with: manifest, installPath: versionDir)
    }

    private func readRecord(at url: URL) -> SDKInstallRecord? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SDKInstallRecord.self, from: data)
    }

    private func writeRecord(_ record: SDKInstallRecord, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        do {
            data = try encoder.encode(record)
        } catch {
            throw registryError(
                code: .updateFailed,
                message: "Could not encode the install record.",
                suggestion: "Try again.",
                diagnostics: ["encodeError": String(describing: error)]
            )
        }
        do {
            let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: temporaryURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            _ = try FileManager.default.replaceItem(at: url, withItemAt: temporaryURL, backupItemName: nil, options: [], resultingItemURL: nil)
        } catch {
            throw registryError(
                code: .updateFailed,
                message: "Could not update the install record.",
                suggestion: "Check the extensions directory permissions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }
    }

    // MARK: - Layout helpers

    private func ensureExtensionsRoot() throws {
        do {
            try FileManager.default.createDirectory(at: Self.extensionsRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw registryError(
                code: .installFailed,
                message: "Could not create the extensions directory.",
                suggestion: "Check the extensions directory permissions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }
    }

    private func versionDirectory(id: String, version: String) -> URL {
        Self.extensionsRoot
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    private func versionDirectories(in idDir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: idDir.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            let path = idDir.appendingPathComponent(name, isDirectory: true).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }.sorted()
    }

    private static func relativePath(of url: URL, to rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        if path == rootPath { return "" }
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return path
    }

    /// Best-effort semver ordering for picking the newest installed version
    /// of an id. Non-semver versions fall back to lexicographic order.
    private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        func core(_ version: String) -> [Int]? {
            let base = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
            let parts = base.split(separator: ".").map(String.init)
            guard parts.count == 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }
            return parts.compactMap { Int($0) }
        }
        if let l = core(lhs), let r = core(rhs) {
            for (a, b) in zip(l, r) {
                if a != b { return a < b ? -1 : 1 }
            }
            // Prerelease < release at equal core.
            let lPre = lhs.contains("-"), rPre = rhs.contains("-")
            if lPre != rPre { return lPre ? -1 : 1 }
            return lhs == rhs ? 0 : (lhs < rhs ? -1 : 1)
        }
        if lhs == rhs { return 0 }
        return lhs < rhs ? -1 : 1
    }

    private func registryError(
        code: SDKErrorCode,
        message: String,
        suggestion: String? = nil,
        diagnostics: [String: String]? = nil
    ) -> SDKError {
        SDKError(code: code, message: message, suggestion: suggestion, diagnostics: diagnostics)
    }
}
