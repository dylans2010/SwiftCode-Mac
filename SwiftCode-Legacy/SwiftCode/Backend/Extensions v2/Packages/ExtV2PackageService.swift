import Foundation
import ZIPFoundation

public struct ExtV2InstalledPackage: Sendable {
    public let directory: URL
    public let manifest: ExtV2VSCodeManifest
    public let compatibility: ExtV2CompatibilityReport

    public init(directory: URL, manifest: ExtV2VSCodeManifest, compatibility: ExtV2CompatibilityReport) {
        self.directory = directory
        self.manifest = manifest
        self.compatibility = compatibility
    }
}

public struct ExtV2PackageService: Sendable {
    public enum Limits {
        public static let maxArchiveBytes: Int64 = 64 * 1024 * 1024
        public static let maxExtractedBytes: Int64 = 512 * 1024 * 1024
        public static let maxEntries = 20_000
        public static let maxRelativePathLength = 512
    }

    public let storage: ExtV2Storage

    public init(storage: ExtV2Storage) {
        self.storage = storage
    }

    public func installDirectory(for extensionId: String) -> URL {
        storage.extensionsDirectory.appendingPathComponent(extensionId, isDirectory: true)
    }

    public func backupDirectory(for extensionId: String) -> URL {
        storage.backupsDirectory.appendingPathComponent("\(extensionId).backup", isDirectory: true)
    }

    public func install(vsixURL: URL, identity: ExtV2Identity) throws -> ExtV2InstalledPackage {
        try Self.validate(extensionId: identity.id)

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: vsixURL.path) else {
            throw ExtV2Error.package("Downloaded package is missing at \(vsixURL.path).")
        }
        let values: URLResourceValues
        do {
            values = try vsixURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw ExtV2Error.package("Could not inspect the downloaded package: \(error.localizedDescription)")
        }
        guard values.isRegularFile == true else {
            throw ExtV2Error.package("Downloaded package is not a regular file.")
        }
        let archiveSize = Int64(values.fileSize ?? 0)
        guard archiveSize > 0 else {
            throw ExtV2Error.package("Downloaded package is empty.")
        }
        guard archiveSize <= Limits.maxArchiveBytes else {
            throw ExtV2Error.package(
                "Package is \(Self.format(bytes: archiveSize)); the limit is \(Self.format(bytes: Limits.maxArchiveBytes)).")
        }

        let archive: Archive
        do {
            archive = try Archive(url: vsixURL, accessMode: .read)
        } catch {
            throw ExtV2Error.package("Downloaded package is not a readable ZIP archive: \(error.localizedDescription)")
        }

        try storage.ensureDirectories()
        let stagingRoot = storage.stagingDirectory
            .appendingPathComponent("\(identity.id)-\(UUID().uuidString)", isDirectory: true)
        let extractionRoot = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        do {
            try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        } catch {
            throw ExtV2Error.package("Could not create a staging directory: \(error.localizedDescription)")
        }

        var entryCount = 0
        var declaredBytes: Int64 = 0
        for entry in archive {
            if Task.isCancelled { throw CancellationError() }
            entryCount += 1
            guard entryCount <= Limits.maxEntries else {
                throw ExtV2Error.package("Package contains more than \(Limits.maxEntries) entries.")
            }
            if entry.path.hasPrefix("__MACOSX/") { continue }
            let relativePath = try Self.validatedRelativePath(entry.path)
            switch entry.type {
            case .symlink:
                throw ExtV2Error.package("Package contains a symbolic link (\(relativePath)); symbolic links are not allowed.")
            case .directory, .file:
                break
            }
            if entry.type == .file {
                let size = Int64(clamping: entry.uncompressedSize)
                declaredBytes += size
                guard declaredBytes <= Limits.maxExtractedBytes else {
                    throw ExtV2Error.package(
                        "Package expands to more than \(Self.format(bytes: Limits.maxExtractedBytes)).")
                }
            }
            let destination = extractionRoot.appendingPathComponent(relativePath)
            guard destination.standardizedFileURL.path.hasPrefix(extractionRoot.standardizedFileURL.path + "/") else {
                throw ExtV2Error.package("Package entry '\(relativePath)' escapes the staging directory.")
            }
            do {
                switch entry.type {
                case .directory:
                    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                case .file:
                    try fileManager.createDirectory(
                        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: destination)
                case .symlink:
                    break
                }
            } catch let error as ExtV2Error {
                throw error
            } catch {
                throw ExtV2Error.package("Could not extract '\(relativePath)': \(error.localizedDescription)")
            }
        }
        guard entryCount > 0 else {
            throw ExtV2Error.package("Package archive contains no entries.")
        }

        try Self.rejectSymlinksAndSpecialFiles(in: extractionRoot)
        try Self.verifyExtractedSize(in: extractionRoot, limit: Limits.maxExtractedBytes)

        let packageRoot = extractionRoot.appendingPathComponent("extension", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExtV2Error.package("Package has no 'extension/' directory; it is not a VSIX layout.")
        }
        let manifestURL = packageRoot.appendingPathComponent("package.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ExtV2Error.package("Package has no extension/package.json.")
        }
        let manifest = try ExtV2ManifestParser.parseFile(at: manifestURL)
        guard manifest.identity.id == identity.id else {
            throw ExtV2Error.package(
                "Package identity '\(manifest.identity.id)' does not match the requested extension '\(identity.id)'.")
        }
        if let main = manifest.main {
            let trimmed = main.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ExtV2Error.package("Manifest declares an empty 'main' entry point.")
            }
            guard !ExtV2ManifestParser.isUnsafeRelativePath(trimmed) else {
                throw ExtV2Error.package("Manifest 'main' entry point escapes the package: \(trimmed)")
            }
            let mainURL = packageRoot.appendingPathComponent(trimmed)
            guard fileManager.fileExists(atPath: mainURL.path) else {
                throw ExtV2Error.package("Manifest 'main' entry point '\(trimmed)' is missing from the package.")
            }
        }

        let compatibility = ExtV2Compatibility.evaluate(manifest: manifest)
        try commit(stagedPackage: extractionRoot, extensionId: identity.id)
        return ExtV2InstalledPackage(
            directory: installDirectory(for: identity.id),
            manifest: manifest,
            compatibility: compatibility)
    }

    public func uninstall(extensionId: String) throws {
        try Self.validate(extensionId: extensionId)
        let fileManager = FileManager.default
        for url in [installDirectory(for: extensionId), backupDirectory(for: extensionId)] {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw ExtV2Error.package("Could not remove \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func commit(stagedPackage: URL, extensionId: String) throws {
        let fileManager = FileManager.default
        let finalDirectory = installDirectory(for: extensionId)
        let backup = backupDirectory(for: extensionId)
        do {
            try fileManager.createDirectory(
                at: finalDirectory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
            let hadPrevious = fileManager.fileExists(atPath: finalDirectory.path)
            if hadPrevious {
                try fileManager.moveItem(at: finalDirectory, to: backup)
            }
            do {
                try fileManager.moveItem(at: stagedPackage, to: finalDirectory)
            } catch {
                if hadPrevious, fileManager.fileExists(atPath: backup.path) {
                    try? fileManager.moveItem(at: backup, to: finalDirectory)
                }
                throw error
            }
        } catch let error as ExtV2Error {
            throw error
        } catch {
            throw ExtV2Error.package(
                "Could not commit the installation for \(extensionId): \(error.localizedDescription)")
        }
    }

    static func validate(extensionId: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !extensionId.isEmpty, extensionId.count <= 214,
              extensionId.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !extensionId.hasPrefix("."), !extensionId.contains("..") else {
            throw ExtV2Error.package("Invalid extension id '\(extensionId)'.")
        }
    }

    private static func validatedRelativePath(_ path: String) throws -> String {
        guard !path.isEmpty else {
            throw ExtV2Error.package("Package contains an entry with an empty path.")
        }
        guard path.count <= Limits.maxRelativePathLength else {
            throw ExtV2Error.package("Package entry path is longer than \(Limits.maxRelativePathLength) characters.")
        }
        guard !path.contains("\0") else {
            throw ExtV2Error.package("Package entry path contains a null byte.")
        }
        guard !path.hasPrefix("/") else {
            throw ExtV2Error.package("Package contains an absolute path: \(path)")
        }
        guard !path.contains("\\") else {
            throw ExtV2Error.package("Package contains a path with a backslash separator: \(path)")
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty else {
            throw ExtV2Error.package("Package contains an entry with an empty path.")
        }
        for component in components {
            guard component != "..", component != "." else {
                throw ExtV2Error.package("Package entry escapes the package: \(path)")
            }
            guard !component.hasSuffix(":") || component.count > 1 else {
                throw ExtV2Error.package("Package entry uses a drive-qualified path: \(path)")
            }
        }
        return components.joined(separator: "/")
    }

    private static func rejectSymlinksAndSpecialFiles(in root: URL) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
            options: [],
            errorHandler: { _, _ in true }) else {
            throw ExtV2Error.package("Could not inspect the extracted package.")
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
            if values.isSymbolicLink == true {
                throw ExtV2Error.package(
                    "Package extracted a symbolic link (\(url.lastPathComponent)); symbolic links are not allowed.")
            }
            guard values.isRegularFile == true || values.isDirectory == true else {
                throw ExtV2Error.package(
                    "Package extracted a special file (\(url.lastPathComponent)); only files and directories are allowed.")
            }
        }
    }

    private static func verifyExtractedSize(in root: URL, limit: Int64) throws {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [],
            errorHandler: { _, _ in true }) else {
            return
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            if total > limit {
                throw ExtV2Error.package("Package expands to more than \(format(bytes: limit)).")
            }
        }
    }

    private static func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
