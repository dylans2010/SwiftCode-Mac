import Foundation
import YcodeSubprocess

public struct InstalledPackage: Sendable {
    public let directory: URL
    public let manifest: VSCodeManifest
    public let compatibility: CompatibilityReport

    public init(directory: URL, manifest: VSCodeManifest, compatibility: CompatibilityReport) {
        self.directory = directory
        self.manifest = manifest
        self.compatibility = compatibility
    }
}

public struct PackageService: Sendable {
    public enum Limits {
        public static let maxArchiveBytes: Int64 = 64 * 1024 * 1024
        public static let maxExtractedBytes: Int64 = 512 * 1024 * 1024
        public static let maxEntries: Int = 20_000
        public static let maxRelativePathLength: Int = 512
    }

    public let storage: ExtensionStorage

    public init(storage: ExtensionStorage) {
        self.storage = storage
    }

    public func installDirectory(for extensionId: String) -> URL {
        storage.extensionsDirectory.appendingPathComponent(extensionId)
    }

    public func backupDirectory(for extensionId: String) -> URL {
        storage.backupsDirectory.appendingPathComponent("\(extensionId).backup")
    }

    public static func validate(extensionId: String) throws {
        guard !extensionId.isEmpty, extensionId.count <= 214 else {
            throw SwiftCodeExtensionError.package("Extension id must be non-empty and at most 214 characters.")
        }
        guard !extensionId.hasPrefix(".") && !extensionId.contains("..") else {
            throw SwiftCodeExtensionError.package("Extension id must not start with '.' or contain '..'.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard extensionId.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw SwiftCodeExtensionError.package("Extension id contains an invalid character.")
        }
    }

    public func install(vsixURL: URL, identity: ExtensionIdentity) throws -> InstalledPackage {
        try Self.validate(extensionId: identity.id)
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: vsixURL.path),
              let size = attributes[.size] as? Int64,
              let type = attributes[.type] as? FileAttributeType, type == .typeRegular else {
            throw SwiftCodeExtensionError.package("VSIX file is missing or is not a regular file.")
        }
        guard size > 0 else { throw SwiftCodeExtensionError.package("VSIX file is empty.") }
        guard size <= Limits.maxArchiveBytes else {
            throw SwiftCodeExtensionError.package("VSIX exceeds the 64 MiB limit.")
        }
        let entries: [ZipEntry]
        do {
            entries = try ZipCentralDirectory.listEntries(of: vsixURL)
        } catch let error as SwiftCodeExtensionError {
            throw error
        } catch {
            throw SwiftCodeExtensionError.package("VSIX is not a readable ZIP archive: \(error.localizedDescription)")
        }
        try validateEntries(entries)
        let staging = storage.stagingDirectory
            .appendingPathComponent("\(identity.id)-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try extract(vsixURL: vsixURL, to: staging)
        try verifyExtractedTree(at: staging)
        let extensionDirectory = staging.appendingPathComponent("extension")
        guard fileManager.fileExists(atPath: extensionDirectory.path) else {
            throw SwiftCodeExtensionError.package("VSIX has no 'extension/' directory.")
        }
        let manifestURL = extensionDirectory.appendingPathComponent("package.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SwiftCodeExtensionError.package("VSIX has no 'extension/package.json'.")
        }
        let manifest = try VSCodeManifestParser.parseFile(at: manifestURL)
        guard manifest.identity.id == identity.id else {
            throw SwiftCodeExtensionError.package(
                "Manifest identity '\(manifest.identity.id)' does not match the requested identity '\(identity.id)'.")
        }
        if let main = manifest.main {
            guard !main.trimmingCharacters(in: .whitespaces).isEmpty,
                  !VSCodeManifestParser.isUnsafeRelativePath(main),
                  fileManager.fileExists(atPath: extensionDirectory.appendingPathComponent(main).path) else {
                throw SwiftCodeExtensionError.package("Manifest 'main' entry point is missing or unsafe.")
            }
        }
        let compatibility = Compatibility.evaluate(manifest: manifest)
        let destination = installDirectory(for: identity.id)
        let backup = backupDirectory(for: identity.id)
        var hadPrevious = false
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: backup)
            do {
                try fileManager.moveItem(at: destination, to: backup)
                hadPrevious = true
            } catch {
                throw SwiftCodeExtensionError.package("Could not back up the previous installation: \(error.localizedDescription)")
            }
        }
        do {
            try fileManager.createDirectory(at: storage.extensionsDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if hadPrevious { try? fileManager.moveItem(at: backup, to: destination) }
            throw SwiftCodeExtensionError.package("Could not commit the installation: \(error.localizedDescription)")
        }
        return InstalledPackage(directory: destination, manifest: manifest, compatibility: compatibility)
    }

    public func uninstall(extensionId: String) throws {
        try? FileManager.default.removeItem(at: installDirectory(for: extensionId))
        try? FileManager.default.removeItem(at: backupDirectory(for: extensionId))
    }

    private func validateEntries(_ entries: [ZipEntry]) throws {
        guard entries.count <= Limits.maxEntries else {
            throw SwiftCodeExtensionError.package("VSIX has more than 20,000 archive entries.")
        }
        var totalUncompressed: Int64 = 0
        for entry in entries {
            if entry.name.hasPrefix("__MACOSX/") { continue }
            try Self.validateRelativePath(entry.name)
            if entry.isSymlink {
                throw SwiftCodeExtensionError.package("VSIX entry '\(entry.name)' is a symlink, which is rejected.")
            }
            if !entry.isFile && !entry.isDirectory {
                throw SwiftCodeExtensionError.package("VSIX entry '\(entry.name)' is not a file or directory.")
            }
            totalUncompressed += entry.uncompressedSize
            guard totalUncompressed <= Limits.maxExtractedBytes else {
                throw SwiftCodeExtensionError.package("VSIX extracts to more than 512 MiB.")
            }
        }
    }

    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty else { throw SwiftCodeExtensionError.package("VSIX contains an entry with an empty path.") }
        guard path.count <= Limits.maxRelativePathLength else {
            throw SwiftCodeExtensionError.package("VSIX entry path exceeds 512 characters.")
        }
        guard !path.contains("\0"), !path.hasPrefix("/"), !path.contains("\\") else {
            throw SwiftCodeExtensionError.package("VSIX entry path '\(path)' is not a safe relative path.")
        }
        if path.count >= 2, path[path.index(path.startIndex, offsetBy: 1)] == ":",
           path[path.startIndex].isLetter {
            throw SwiftCodeExtensionError.package("VSIX entry path '\(path)' is drive-qualified.")
        }
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            if component == "." || component == ".." {
                throw SwiftCodeExtensionError.package("VSIX entry path '\(path)' contains a '.' or '..' component.")
            }
        }
    }

    private func extract(vsixURL: URL, to staging: URL) throws {
#if os(macOS)
        let output = try Subprocess.run("/usr/bin/ditto", ["-x", "-k", vsixURL.path, staging.path])
        guard output.status == 0 else {
            throw SwiftCodeExtensionError.package("VSIX extraction failed: \(output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw SwiftCodeExtensionError.package("VSIX extraction needs the `unzip` command-line tool, which is not installed on this system.")
        }
        let output = try Subprocess.run("/usr/bin/unzip", ["-q", "-o", vsixURL.path, "-d", staging.path])
        guard output.status == 0 else {
            throw SwiftCodeExtensionError.package("VSIX extraction failed: \(output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#endif
    }

    private func verifyExtractedTree(at staging: URL) throws {
        let fileManager = FileManager.default
        let stagingPath = staging.standardized.path
        guard let enumerator = fileManager.enumerator(at: staging, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey]) else {
            throw SwiftCodeExtensionError.package("Could not enumerate the extracted VSIX.")
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard url.standardized.path == stagingPath || url.standardized.path.hasPrefix(stagingPath + "/") else {
                throw SwiftCodeExtensionError.package("Extracted path escapes the staging directory.")
            }
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            if values?.isSymbolicLink == true {
                throw SwiftCodeExtensionError.package("Extracted tree contains a symlink at '\(url.lastPathComponent)'.")
            }
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
                guard total <= Limits.maxExtractedBytes else {
                    throw SwiftCodeExtensionError.package("Extracted VSIX exceeds 512 MiB on disk.")
                }
            } else if values?.isDirectory != true {
                throw SwiftCodeExtensionError.package("Extracted tree contains a special file at '\(url.lastPathComponent)'.")
            }
        }
    }

    public static func validateSwiftCodePackage(at root: URL, manifest: SwiftCodeManifest) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SwiftCodeExtensionError.package("SwiftCode package root is not a directory.")
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("swiftcode.json").path) else {
            throw SwiftCodeExtensionError.package("SwiftCode package has no swiftcode.json at its root.")
        }
        let entrypoint = root.appendingPathComponent(manifest.runtime.entrypoint)
        let resolved = entrypoint.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              FileManager.default.fileExists(atPath: resolved.path) else {
            throw SwiftCodeExtensionError.package("SwiftCode entrypoint does not resolve to a file inside the package (pathTraversal).")
        }
        let forbiddenExecutableExtensions: Set<String> = ["sh", "bin", "exe", "dylib", "so"]
        var entries = 0
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            throw SwiftCodeExtensionError.package("Could not enumerate the SwiftCode package.")
        }
        for case let url as URL in enumerator {
            entries += 1
            guard entries <= 10_000 else {
                throw SwiftCodeExtensionError.package("SwiftCode package exceeds 10,000 entries.")
            }
            let name = url.lastPathComponent
            guard !name.contains("\0"), name.utf8.count <= 255 else {
                throw SwiftCodeExtensionError.package("SwiftCode package has an over-long or NUL-containing file name.")
            }
            if name == ".env" || url.pathComponents.contains("node_modules") {
                throw SwiftCodeExtensionError.package("SwiftCode package must not contain '.env' files or 'node_modules'.")
            }
            if forbiddenExecutableExtensions.contains(url.pathExtension.lowercased()) {
                throw SwiftCodeExtensionError.package("SwiftCode package contains a forbidden executable '.\(url.pathExtension)' file.")
            }
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
                guard total <= 100 * 1024 * 1024 else {
                    throw SwiftCodeExtensionError.package("SwiftCode package exceeds 100 MB.")
                }
            }
        }
    }
}

struct ZipEntry: Sendable {
    let name: String
    let uncompressedSize: Int64
    let isSymlink: Bool
    let isDirectory: Bool

    var isFile: Bool { !isDirectory }
}

enum ZipCentralDirectory {
    static func listEntries(of url: URL) throws -> [ZipEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw SwiftCodeExtensionError.package("Could not read the VSIX file: \(error.localizedDescription)")
        }
        return try listEntries(data: data)
    }

    static func listEntries(data: Data) throws -> [ZipEntry] {
        guard let eocd = findEndOfCentralDirectory(in: data) else {
            throw SwiftCodeExtensionError.package("VSIX has no ZIP end-of-central-directory record.")
        }
        let disk = readUInt16(data, at: eocd + 4)
        let cdDisk = readUInt16(data, at: eocd + 6)
        let count = Int(readUInt16(data, at: eocd + 10))
        let cdSize = Int(readUInt32(data, at: eocd + 12))
        let cdOffset = Int(readUInt32(data, at: eocd + 16))
        guard disk == 0, cdDisk == 0 else {
            throw SwiftCodeExtensionError.package("Multi-disk ZIP archives are not supported.")
        }
        guard cdOffset + cdSize <= data.count else {
            throw SwiftCodeExtensionError.package("ZIP central directory is truncated.")
        }
        var entries: [ZipEntry] = []
        var cursor = cdOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, readUInt32(data, at: cursor) == 0x02014B50 else {
                throw SwiftCodeExtensionError.package("ZIP central directory is malformed.")
            }
            let uncompressedSize32 = readUInt32(data, at: cursor + 24)
            let compressedSize32 = readUInt32(data, at: cursor + 20)
            guard uncompressedSize32 != 0xFFFF_FFFF, compressedSize32 != 0xFFFF_FFFF else {
                throw SwiftCodeExtensionError.package("ZIP64 archives are not supported.")
            }
            let nameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let externalAttributes = readUInt32(data, at: cursor + 38)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw SwiftCodeExtensionError.package("ZIP central directory entry name is truncated.")
            }
            let nameData = data[nameStart..<(nameStart + nameLength)]
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw SwiftCodeExtensionError.package("ZIP entry name is not valid UTF-8.")
            }
            let unixMode = (externalAttributes >> 16) & 0xFFFF
            let fileType = unixMode & 0o170000
            let isSymlink = fileType == 0o120000
            let isDirectory = name.hasSuffix("/") || fileType == 0o040000
            entries.append(ZipEntry(name: name, uncompressedSize: Int64(uncompressedSize32),
                                    isSymlink: isSymlink, isDirectory: isDirectory))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let searchStart = data.count > (65557 + 22) ? data.count - (65557 + 22) : 0
        var index = data.count - 22
        while index >= searchStart {
            if readUInt32(data, at: index) == 0x06054B50 { return index }
            index -= 1
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}
