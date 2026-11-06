import Foundation
import YcodeSubprocess

// MARK: - VSIX package service (spec §6.3)

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

/// Installs VSIX archives. ZIP handling: entry validation reads the
/// archive's central directory with a small pure-Swift reader (no new
/// SPM dependency — see the note below); extraction itself runs the
/// fixed-argv system tools from the Wave 5 archive pattern
/// (`/usr/bin/ditto -x -k` on macOS, `/usr/bin/unzip -q -o` on Linux).
/// No package script is ever executed anywhere in the pipeline.
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

    /// Validates an extension id: non-empty, ≤ 214 chars, only
    /// alphanumerics plus `._-`, no leading `.`, no `..`.
    public static func validate(extensionId: String) throws {
        guard !extensionId.isEmpty, extensionId.count <= 214 else {
            throw YcodeExtensionError.package("Extension id must be non-empty and at most 214 characters.")
        }
        guard !extensionId.hasPrefix(".") && !extensionId.contains("..") else {
            throw YcodeExtensionError.package("Extension id must not start with '.' or contain '..'.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard extensionId.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw YcodeExtensionError.package("Extension id contains an invalid character.")
        }
    }

    /// The §6.3 install pipeline. Blocking (runs system tools); call
    /// from a background task, never the main thread.
    public func install(vsixURL: URL, identity: ExtensionIdentity) throws -> InstalledPackage {
        try Self.validate(extensionId: identity.id)
        let fileManager = FileManager.default
        guard let attributes = try? fileManager.attributesOfItem(atPath: vsixURL.path),
              let size = attributes[.size] as? Int64,
              let type = attributes[.type] as? FileAttributeType, type == .typeRegular else {
            throw YcodeExtensionError.package("VSIX file is missing or is not a regular file.")
        }
        guard size > 0 else { throw YcodeExtensionError.package("VSIX file is empty.") }
        guard size <= Limits.maxArchiveBytes else {
            throw YcodeExtensionError.package("VSIX exceeds the 64 MiB limit.")
        }
        let entries: [ZipEntry]
        do {
            entries = try ZipCentralDirectory.listEntries(of: vsixURL)
        } catch let error as YcodeExtensionError {
            throw error
        } catch {
            throw YcodeExtensionError.package("VSIX is not a readable ZIP archive: \(error.localizedDescription)")
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
            throw YcodeExtensionError.package("VSIX has no 'extension/' directory.")
        }
        let manifestURL = extensionDirectory.appendingPathComponent("package.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw YcodeExtensionError.package("VSIX has no 'extension/package.json'.")
        }
        let manifest = try VSCodeManifestParser.parseFile(at: manifestURL)
        guard manifest.identity.id == identity.id else {
            throw YcodeExtensionError.package(
                "Manifest identity '\(manifest.identity.id)' does not match the requested identity '\(identity.id)'.")
        }
        if let main = manifest.main {
            guard !main.trimmingCharacters(in: .whitespaces).isEmpty,
                  !VSCodeManifestParser.isUnsafeRelativePath(main),
                  fileManager.fileExists(atPath: extensionDirectory.appendingPathComponent(main).path) else {
                throw YcodeExtensionError.package("Manifest 'main' entry point is missing or unsafe.")
            }
        }
        let compatibility = Compatibility.evaluate(manifest: manifest)
        // Commit with one directory move; the previous installation is
        // moved aside first and restored if the commit fails.
        let destination = installDirectory(for: identity.id)
        let backup = backupDirectory(for: identity.id)
        var hadPrevious = false
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: backup)
            do {
                try fileManager.moveItem(at: destination, to: backup)
                hadPrevious = true
            } catch {
                throw YcodeExtensionError.package("Could not back up the previous installation: \(error.localizedDescription)")
            }
        }
        do {
            try fileManager.createDirectory(at: storage.extensionsDirectory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if hadPrevious { try? fileManager.moveItem(at: backup, to: destination) }
            throw YcodeExtensionError.package("Could not commit the installation: \(error.localizedDescription)")
        }
        return InstalledPackage(directory: destination, manifest: manifest, compatibility: compatibility)
    }

    /// Idempotent: an already-removed dir is not an error.
    public func uninstall(extensionId: String) throws {
        try? FileManager.default.removeItem(at: installDirectory(for: extensionId))
        try? FileManager.default.removeItem(at: backupDirectory(for: extensionId))
    }

    // MARK: Entry validation (single pass, before anything is written)

    private func validateEntries(_ entries: [ZipEntry]) throws {
        guard entries.count <= Limits.maxEntries else {
            throw YcodeExtensionError.package("VSIX has more than 20,000 archive entries.")
        }
        var totalUncompressed: Int64 = 0
        for entry in entries {
            if entry.name.hasPrefix("__MACOSX/") { continue } // Skipped.
            try Self.validateRelativePath(entry.name)
            if entry.isSymlink {
                throw YcodeExtensionError.package("VSIX entry '\(entry.name)' is a symlink, which is rejected.")
            }
            if !entry.isFile && !entry.isDirectory {
                throw YcodeExtensionError.package("VSIX entry '\(entry.name)' is not a file or directory.")
            }
            totalUncompressed += entry.uncompressedSize
            guard totalUncompressed <= Limits.maxExtractedBytes else {
                throw YcodeExtensionError.package("VSIX extracts to more than 512 MiB.")
            }
        }
    }

    /// Relative path rules (§6.3 step 4): non-empty, ≤ 512 chars, no
    /// NUL, not absolute, no backslash separator, no `.`/`..`
    /// components, no drive-qualified `X:` component.
    static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty else { throw YcodeExtensionError.package("VSIX contains an entry with an empty path.") }
        guard path.count <= Limits.maxRelativePathLength else {
            throw YcodeExtensionError.package("VSIX entry path exceeds 512 characters.")
        }
        guard !path.contains("\0"), !path.hasPrefix("/"), !path.contains("\\") else {
            throw YcodeExtensionError.package("VSIX entry path '\(path)' is not a safe relative path.")
        }
        if path.count >= 2, path[path.index(path.startIndex, offsetBy: 1)] == ":",
           path[path.startIndex].isLetter {
            throw YcodeExtensionError.package("VSIX entry path '\(path)' is drive-qualified.")
        }
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            if component == "." || component == ".." {
                throw YcodeExtensionError.package("VSIX entry path '\(path)' contains a '.' or '..' component.")
            }
        }
    }

    // MARK: Extraction + post-extraction verification

    private func extract(vsixURL: URL, to staging: URL) throws {
#if os(macOS)
        let output = try Subprocess.run("/usr/bin/ditto", ["-x", "-k", vsixURL.path, staging.path])
        guard output.status == 0 else {
            throw YcodeExtensionError.package("VSIX extraction failed: \(output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw YcodeExtensionError.package("VSIX extraction needs the `unzip` command-line tool, which is not installed on this system.")
        }
        let output = try Subprocess.run("/usr/bin/unzip", ["-q", "-o", vsixURL.path, "-d", staging.path])
        guard output.status == 0 else {
            throw YcodeExtensionError.package("VSIX extraction failed: \(output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
#endif
    }

    /// Post-extraction verification on disk (ZIP headers can lie):
    /// reject any symlink or special file; verify the real extracted
    /// byte total ≤ 512 MiB; every destination must stay inside staging.
    private func verifyExtractedTree(at staging: URL) throws {
        let fileManager = FileManager.default
        let stagingPath = staging.standardized.path
        guard let enumerator = fileManager.enumerator(at: staging, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey]) else {
            throw YcodeExtensionError.package("Could not enumerate the extracted VSIX.")
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard url.standardized.path == stagingPath || url.standardized.path.hasPrefix(stagingPath + "/") else {
                throw YcodeExtensionError.package("Extracted path escapes the staging directory.")
            }
            let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            if values?.isSymbolicLink == true {
                throw YcodeExtensionError.package("Extracted tree contains a symlink at '\(url.lastPathComponent)'.")
            }
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
                guard total <= Limits.maxExtractedBytes else {
                    throw YcodeExtensionError.package("Extracted VSIX exceeds 512 MiB on disk.")
                }
            } else if values?.isDirectory != true {
                throw YcodeExtensionError.package("Extracted tree contains a special file at '\(url.lastPathComponent)'.")
            }
        }
    }

    /// `swiftcode.json` package validation (spec §6.3, folded in from
    /// `SDKPackageValidator`): root must be a directory, `swiftcode.json`
    /// must exist, entrypoint must resolve inside the package
    /// (symlinks resolved, max depth 40), walk caps of 10,000 entries /
    /// 100 MB total / 255-byte names / no NUL.
    ///
    /// UNVERIFIED (U-4): whether Legacy's walk enforces the declared
    /// executable-extension set and the `.env`/`node_modules`
    /// exclusions. This implementation enforces the extension set and
    /// the exclusions per the validator's header comment and records
    /// that as a decision here.
    public static func validateSwiftCodePackage(at root: URL, manifest: SwiftCodeManifest) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw YcodeExtensionError.package("SwiftCode package root is not a directory.")
        }
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("swiftcode.json").path) else {
            throw YcodeExtensionError.package("SwiftCode package has no swiftcode.json at its root.")
        }
        let entrypoint = root.appendingPathComponent(manifest.runtime.entrypoint)
        let resolved = entrypoint.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              FileManager.default.fileExists(atPath: resolved.path) else {
            throw YcodeExtensionError.package("SwiftCode entrypoint does not resolve to a file inside the package (pathTraversal).")
        }
        let forbiddenExecutableExtensions: Set<String> = ["sh", "bin", "exe", "dylib", "so"]
        var entries = 0
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            throw YcodeExtensionError.package("Could not enumerate the SwiftCode package.")
        }
        for case let url as URL in enumerator {
            entries += 1
            guard entries <= 10_000 else {
                throw YcodeExtensionError.package("SwiftCode package exceeds 10,000 entries.")
            }
            let name = url.lastPathComponent
            guard !name.contains("\0"), name.utf8.count <= 255 else {
                throw YcodeExtensionError.package("SwiftCode package has an over-long or NUL-containing file name.")
            }
            if name == ".env" || url.pathComponents.contains("node_modules") {
                throw YcodeExtensionError.package("SwiftCode package must not contain '.env' files or 'node_modules'.")
            }
            if forbiddenExecutableExtensions.contains(url.pathExtension.lowercased()) {
                throw YcodeExtensionError.package("SwiftCode package contains a forbidden executable '.\(url.pathExtension)' file.")
            }
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
                guard total <= 100 * 1024 * 1024 else {
                    throw YcodeExtensionError.package("SwiftCode package exceeds 100 MB.")
                }
            }
        }
    }
}

// MARK: - Minimal ZIP central-directory reader

/// One central-directory entry: name, uncompressed size, and the
/// Unix file-type bits from the external attributes (symlink
/// detection). Only the central directory is read; no entry data is
/// decompressed here. ZIP64 archives are rejected (sizes stored as
/// 0xFFFFFFFF), as are multi-disk archives.
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
            throw YcodeExtensionError.package("Could not read the VSIX file: \(error.localizedDescription)")
        }
        return try listEntries(data: data)
    }

    static func listEntries(data: Data) throws -> [ZipEntry] {
        guard let eocd = findEndOfCentralDirectory(in: data) else {
            throw YcodeExtensionError.package("VSIX has no ZIP end-of-central-directory record.")
        }
        let disk = readUInt16(data, at: eocd + 4)
        let cdDisk = readUInt16(data, at: eocd + 6)
        let count = Int(readUInt16(data, at: eocd + 10))
        let cdSize = Int(readUInt32(data, at: eocd + 12))
        let cdOffset = Int(readUInt32(data, at: eocd + 16))
        guard disk == 0, cdDisk == 0 else {
            throw YcodeExtensionError.package("Multi-disk ZIP archives are not supported.")
        }
        guard cdOffset + cdSize <= data.count else {
            throw YcodeExtensionError.package("ZIP central directory is truncated.")
        }
        var entries: [ZipEntry] = []
        var cursor = cdOffset
        for _ in 0..<count {
            guard cursor + 46 <= data.count, readUInt32(data, at: cursor) == 0x02014B50 else {
                throw YcodeExtensionError.package("ZIP central directory is malformed.")
            }
            let uncompressedSize32 = readUInt32(data, at: cursor + 24)
            let compressedSize32 = readUInt32(data, at: cursor + 20)
            guard uncompressedSize32 != 0xFFFF_FFFF, compressedSize32 != 0xFFFF_FFFF else {
                throw YcodeExtensionError.package("ZIP64 archives are not supported.")
            }
            let nameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let externalAttributes = readUInt32(data, at: cursor + 38)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else {
                throw YcodeExtensionError.package("ZIP central directory entry name is truncated.")
            }
            let nameData = data[nameStart..<(nameStart + nameLength)]
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw YcodeExtensionError.package("ZIP entry name is not valid UTF-8.")
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
        // The EOCD is 22 bytes; a comment of up to 64 KiB may follow it.
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
