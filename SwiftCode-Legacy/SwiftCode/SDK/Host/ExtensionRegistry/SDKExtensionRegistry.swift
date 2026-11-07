import CryptoKit
import Foundation
import os

public struct SDKInstalledExtension: Codable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let packageDigest: String
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

public actor SDKExtensionRegistry {

    public static let shared = SDKExtensionRegistry()

    public nonisolated static var extensionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftCode/Extensions", isDirectory: true)
    }

    private static let metadataFileName = ".sdk-install.json"

    private static let manifestFileName = "swiftcode.json"

    private static let digestExcludedNames: Set<String> = [metadataFileName]

    private static let digestChunkSize = 10 * 1024 * 1024

    private static let log = Logger(subsystem: "com.swiftcode.sdk", category: "sdk-extension-registry")

    private init() {}

    private var cache: [String: SDKInstalledExtension] = [:]

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

    public func installedExtension(id: String) -> SDKInstalledExtension? {
        cache[id]
    }

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
            guard !relative.isEmpty else { continue }
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

        if let existing = cache[ext.id], compareVersions(existing.version, ext.version) >= 0 {
            return
        }
        cache[ext.id] = ext
    }

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

        let idDir = versionDir.deletingLastPathComponent()
        if (try? FileManager.default.contentsOfDirectory(atPath: idDir.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: idDir)
        }

        if let cached = cache[extensionID], cached.version == version {
            cache.removeValue(forKey: extensionID)
        }
    }

    private func readInstall(id: String, version: String, at versionDir: URL) -> SDKInstalledExtension? {
        let recordURL = versionDir.appendingPathComponent(Self.metadataFileName, isDirectory: false)
        guard let record = readRecord(at: recordURL) else {
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): missing or unreadable .sdk-install.json")
            return nil
        }
        guard record.id == id, record.version == version else {
            Self.log.error("Skipping install \(id, privacy: .public)/\(version, privacy: .public): record identity does not match directory layout")
            return nil
        }

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
