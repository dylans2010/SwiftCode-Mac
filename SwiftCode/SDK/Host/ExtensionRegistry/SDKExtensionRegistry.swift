import CryptoKit
import Foundation
import os

// MARK: - SDKInstalledExtension
//
// The host's *record* of one installed extension (spec §17: controlled
// directory, identity + version + digest recorded). This is data only — the
// install/update/uninstall FLOWS (copy, validate, rollback, re-approval on
// digest change per spec §8.7) arrive with the CLI phase and live elsewhere;
// `SDKExtensionRegistry` never copies package trees itself.

public struct SDKInstalledExtension: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    /// SHA-256 hex digest of the installed tree at install/update time
    /// (computed by `SDKExtensionRegistry.computeDigest(of:)`).
    public let packageDigest: String
    /// Absolute path of the installed version directory.
    public let installPath: String
    public let installedAt: Date
    public let updatedAt: Date
    public let enabled: Bool
    public let manifest: SDKManifest

    public init(
        id: String,
        name: String,
        version: String,
        packageDigest: String,
        installPath: String,
        installedAt: Date,
        updatedAt: Date,
        enabled: Bool,
        manifest: SDKManifest
    ) {
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

// MARK: - SDKInstallRecord
//
// The on-disk metadata persisted as `.sdk-install.json` inside each
// `<extensionsRoot>/<id>/<version>/` directory. Identical to
// `SDKInstalledExtension` minus `manifest`: the manifest is re-read and
// re-validated from `swiftcode.json` on every scan, so a tampered install
// fails closed instead of being trusted from the record.

private struct SDKInstallRecord: Codable, Sendable {
    var id: String
    var name: String
    var version: String
    var packageDigest: String
    var installPath: String
    var installedAt: Date
    var updatedAt: Date
    var enabled: Bool

    init(from ext: SDKInstalledExtension) {
        self.id = ext.id
        self.name = ext.name
        self.version = ext.version
        self.packageDigest = ext.packageDigest
        self.installPath = ext.installPath
        self.installedAt = ext.installedAt
        self.updatedAt = ext.updatedAt
        self.enabled = ext.enabled
    }

    func installedExtension(with manifest: SDKManifest) -> SDKInstalledExtension {
        SDKInstalledExtension(
            id: id,
            name: name,
            version: version,
            packageDigest: packageDigest,
            installPath: installPath,
            installedAt: installedAt,
            updatedAt: updatedAt,
            enabled: enabled,
            manifest: manifest
        )
    }
}

// MARK: - SDKExtensionRegistry
//
// Installed-extension registry (spec §17). Owns the controlled install
// directory `~/Library/Application Support/SwiftCode/Extensions`, laid out as
// `<root>/<extension-id>/<version>/`, and the `.sdk-install.json` metadata
// record in each version directory.
//
// Responsibilities:
//   - `scan()` — discover installed extensions, re-validate each manifest
//     with `SDKManifestValidator` (fail closed on tampering).
//   - `computeDigest(of:)` — canonical SHA-256 digest of an installed tree.
//   - `recordInstall(_:)` — persist the install/update metadata record.
//   - `setEnabled(_:extensionID:)` — flip the enabled flag (the runtime
//     coordinator deactivates separately).
//   - `removeInstallRecord(extensionID:version:)` — delete a version dir
//     (the uninstall flow deactivates first).
//
// This registry never copies package trees, never validates packages (that
// is `SDKPackageValidator`'s job, run by the install/update flow before
// `recordInstall`), and never grants capabilities (the capability broker
// re-evaluates grants when the digest changes, spec §8.7).

public actor SDKExtensionRegistry {

    // MARK: - Shared instance

    public static let shared = SDKExtensionRegistry()

    // MARK: - Layout

    /// The controlled extensions directory. Created on demand.
    public nonisolated static var extensionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftCode/Extensions", isDirectory: true)
    }

    /// Name of the host-written metadata file inside each installed version dir.
    private static let metadataFileName = ".sdk-install.json"

    /// Name of the manifest file expected at each installed version dir root.
    private static let manifestFileName = "swiftcode.json"

    /// `.sdk-install.json` is host metadata, not extension content: it must
    /// not participate in the package digest (a package digest that included
    /// its own record could never be stable).
    private static let digestExcludedNames: Set<String> = [metadataFileName]

    /// Streaming chunk size for digesting file bytes (10 MB).
    private static let digestChunkSize = 10 * 1024 * 1024

    private static let log = Logger(subsystem: "com.swiftcode.sdk", category: "sdk-extension-registry")

    private init() {}

    // MARK: - In-memory cache

    /// Last `scan()` result, keyed by extension id. Refreshed only by `scan()`.
    private var cache: [String: SDKInstalledExtension] = [:]

    // MARK: - Root management

    /// Creates the extensions root on demand (idempotent).
    private func ensureExtensionsRoot() throws {
        let root = Self.extensionsRoot
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw registryError(
                    code: .installFailed,
                    message: "The extensions directory exists but is not a directory.",
                    suggestion: "Remove the file at the extensions location and try again."
                )
            }
            return
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw registryError(
                code: .installFailed,
                message: "Could not create the extensions directory.",
                suggestion: "Check that the Library/Application Support directory is writable.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }
    }

    // MARK: - Scan

    /// Walks `<root>/<id>/<version>/`, re-validates each manifest, and
    /// returns the installed extensions sorted by id.
    ///
    /// An entry is recognized only when BOTH are present:
    ///   - `swiftcode.json` — decoded AND re-validated with
    ///     `SDKManifestValidator` (a tampered install fails closed); the
    ///     manifest's id/version must match the directory layout.
    ///   - `.sdk-install.json` — the host's install record; its id/version
    ///     must also match the directory layout.
    ///
    /// Malformed entries are skipped (logged via `os_log`) without aborting
    /// the whole scan. The in-memory cache is replaced with the result.
    public func scan() throws -> [SDKInstalledExtension] {
        try ensureExtensionsRoot()
        let root = Self.extensionsRoot
        let fileManager = FileManager.default

        let idNames: [String]
        do {
            idNames = try fileManager.contentsOfDirectory(atPath: root.path)
        } catch {
            throw registryError(
                code: .installFailed,
                message: "Could not read the extensions directory.",
                suggestion: "Check the extensions directory permissions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }

        var found: [String: SDKInstalledExtension] = [:]
        for idName in idNames.sorted() {
            let idDir = root.appendingPathComponent(idName, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: idDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            for versionName in versionDirectories(in: idDir) {
                let versionDir = idDir.appendingPathComponent(versionName, isDirectory: true)
                if let ext = readInstall(id: idName, version: versionName, at: versionDir) {
                    // If multiple version dirs exist for one id, keep the
                    // newest recorded version (semver-aware when possible).
                    if let existing = found[idName],
                       compareVersions(existing.version, ext.version) >= 0 {
                        continue
                    }
                    found[idName] = ext
                }
            }
        }

        cache = found
        return found.values.sorted { $0.id < $1.id }
    }

    /// Returns the in-memory cache entry for `id` (refreshed only by
    /// `scan()`). Returns `nil` when never scanned or not installed.
    public func installedExtension(id: String) -> SDKInstalledExtension? {
        cache[id]
    }

    // MARK: - Digest

    /// Computes the canonical SHA-256 digest of an installed tree, returned
    /// as lowercase hex.
    ///
    /// The digest covers every entry under `directory` in sorted relative
    /// path order. For each entry the hasher absorbs:
    ///   1. the relative path (UTF-8) + NUL,
    ///   2. an entry-kind byte (`d` directory, `f` file, `l` symlink) + NUL,
    ///   3. the content: streamed file bytes (10 MB chunks — large files are
    ///      never loaded whole), the symlink destination string, or nothing
    ///      for directories.
    ///
    /// `.sdk-install.json` is excluded: it is host-written metadata, not
    /// extension content, and including it would make the digest unstable.
    /// Relative paths are computed against `directory` itself, so the digest
    /// is independent of where the tree lives on disk.
    public func computeDigest(of directory: URL) throws -> String {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw registryError(
                code: .packageIntegrityFailure,
                message: "Could not compute the extension digest: the installed directory is missing.",
                suggestion: "Reinstall the extension and try again."
            )
        }

        let rootPath = directory.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var ioError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, error in
                ioError = error
                return false
            }
        ) else {
            throw registryError(
                code: .packageIntegrityFailure,
                message: "Could not read the installed extension for digesting.",
                suggestion: "Check the installed extension directory permissions and try again."
            )
        }

        var relativePaths: [String] = []
        for case let url as URL in enumerator {
            let relative = Self.relativePath(of: url, to: rootPath)
            guard !relative.isEmpty else { continue } // skip the root itself
            let lastComponent = (relative as NSString).lastPathComponent
            guard !Self.digestExcludedNames.contains(lastComponent) else {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            relativePaths.append(relative)
        }
        if let ioError {
            throw registryError(
                code: .packageIntegrityFailure,
                message: "Could not read the installed extension for digesting.",
                suggestion: "Check the installed extension directory permissions and try again.",
                diagnostics: ["ioError": String(describing: ioError)]
            )
        }

        var hasher = SHA256()
        let kindKeys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        for relative in relativePaths.sorted() {
            let url = URL(fileURLWithPath: rootPath).appendingPathComponent(relative)
            let kindValues = try? url.resourceValues(forKeys: kindKeys)
            let kind: UInt8
            if kindValues?.isSymbolicLink == true {
                kind = UInt8(ascii: "l")
            } else if kindValues?.isRegularFile == true {
                kind = UInt8(ascii: "f")
            } else {
                kind = UInt8(ascii: "d")
            }
            hasher.update(data: Data(relative.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data([kind]))
            hasher.update(data: Data([0]))
            switch kind {
            case UInt8(ascii: "f"):
                try hashFileContents(at: url, into: &hasher)
            case UInt8(ascii: "l"):
                let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
                hasher.update(data: Data(target.utf8))
            default:
                break
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Streams a file's bytes into the hasher in 10 MB chunks.
    private func hashFileContents(at url: URL, into hasher: inout SHA256) throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw registryError(
                code: .packageIntegrityFailure,
                message: "Could not read an installed file while computing the extension digest.",
                suggestion: "Check the installed extension directory permissions and try again.",
                diagnostics: ["path": url.lastPathComponent, "ioError": String(describing: error)]
            )
        }
        defer { try? handle.close() }
        do {
            while true {
                guard let chunk = try handle.read(upToCount: Self.digestChunkSize), !chunk.isEmpty else {
                    break
                }
                hasher.update(data: chunk)
            }
        } catch {
            throw registryError(
                code: .packageIntegrityFailure,
                message: "Could not read an installed file while computing the extension digest.",
                suggestion: "Check the installed extension directory permissions and try again.",
                diagnostics: ["path": url.lastPathComponent, "ioError": String(describing: error)]
            )
        }
    }

    // MARK: - Record install / update

    /// Persists the `.sdk-install.json` metadata record for an installed
    /// (or updated) extension: identity, version, digest, paths, timestamps,
    /// and the enabled flag — everything except the manifest, which is
    /// re-read and re-validated from `swiftcode.json` on scan.
    ///
    /// Called by the install/update flows AFTER the package has been
    /// validated and copied into place; it never copies trees itself. The
    /// write is atomic (temp file + replace) and the record is written with
    /// 0600 permissions and sorted keys. An existing record at the same
    /// version is replaced (updates are gated by the update flow, which
    /// enforces explicit-update semantics and grant re-evaluation on digest
    /// change per spec §8.7).
    public func recordInstall(_ ext: SDKInstalledExtension) throws {
        try ensureExtensionsRoot()
        let versionDir = versionDirectory(id: ext.id, version: ext.version)
        do {
            try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        } catch {
            throw registryError(
                code: .installFailed,
                message: "Could not create the installed extension directory.",
                suggestion: "Check the extensions directory permissions and try again.",
                diagnostics: ["ioError": String(describing: error)]
            )
        }

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
    /// uninstall view's job (it calls `SDKGrantStore.revokeAll(for:)` next);
    /// stored values are deleted here regardless of grant state.
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
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): missing or unreadable .sdk-install.json")
            return nil
        }
        guard record.id == id, record.version == version else {
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): record identity does not match directory layout")
            return nil
        }

        // 2. Manifest: re-read AND re-validate. A tampered swiftcode.json
        //    fails closed here — the record alone is never trusted.
        let manifestURL = versionDir.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): swiftcode.json unreadable")
            return nil
        }
        let manifest: SDKManifest
        do {
            manifest = try SDKManifestValidator.validate(data: manifestData)
        } catch {
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): manifest re-validation failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        guard manifest.id == id, manifest.version == version else {
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): manifest identity does not match directory layout")
            return nil
        }

        return record.installedExtension(with: manifest)
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
