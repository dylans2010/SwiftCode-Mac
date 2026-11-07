import Foundation

public struct ImportedProjectDirectory: Sendable {
    public let name: String
    public let directoryURL: URL

    public init(name: String, directoryURL: URL) {
        self.name = name
        self.directoryURL = directoryURL
    }
}

public final class ProjectZipImporter: Sendable {
    public static let shared = ProjectZipImporter()
    private init() {}

    public func exportZip(projectURL: URL, projectName: String) async throws -> URL {
        let fm = FileManager.default
        let zipName = "\(projectName).zip"
        let destURL = fm.temporaryDirectory.appendingPathComponent(zipName)
        try? fm.removeItem(at: destURL)
        try zipDirectory(projectURL, to: destURL)
        return destURL
    }

    public func importZip(at zipURL: URL, into baseDirectory: URL? = nil) async throws -> ImportedProjectDirectory {
        let fm = FileManager.default
        let projectName = zipURL.deletingPathExtension().lastPathComponent
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try unzip(zipURL, to: tempDir)

        let extractedRoot = try findExtractedRoot(in: tempDir)
        let sanitized = sanitizeName(projectName)

        let baseDir = baseDirectory ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftCode Projects", isDirectory: true)
        var finalName = sanitized
        var destDir = baseDir.appendingPathComponent(finalName)
        var counter = 2
        while fm.fileExists(atPath: destDir.path) {
            finalName = "\(sanitized) \(counter)"
            destDir = baseDir.appendingPathComponent(finalName)
            counter += 1
        }

        try copyContents(from: extractedRoot, to: destDir)

        return ImportedProjectDirectory(name: finalName, directoryURL: destDir)
    }

    private func runTool(_ path: String, _ args: [String], currentDirectory: URL? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ZipImporterError.extractionFailed
        }
    }

    private func zipDirectory(_ directory: URL, to destURL: URL) throws {
        #if os(macOS)
        try runTool("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, destURL.path])
        #else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/zip") else {
            throw ZipImporterError.extractionFailed
        }
        try runTool("/usr/bin/zip", ["-r", "-q", destURL.path, "."], currentDirectory: directory)
        #endif
    }

    private func unzip(_ zipURL: URL, to destination: URL) throws {
        #if os(macOS)
        try runTool("/usr/bin/ditto", ["-x", "-k", zipURL.path, destination.path])
        #else
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
            throw ZipImporterError.extractionFailed
        }
        try runTool("/usr/bin/unzip", ["-q", "-o", zipURL.path, "-d", destination.path])
        #endif
    }

    private func findExtractedRoot(in directory: URL) throws -> URL {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        if contents.count == 1,
           let single = contents.first,
           (try? single.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return single
        }
        return directory
    }

    private func copyContents(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for item in contents {
            let itemName = item.lastPathComponent

            guard !itemName.contains(".."), !itemName.hasPrefix("/") else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            let destItem = destination.appendingPathComponent(itemName)

            guard destItem.path.hasPrefix(destination.path) else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            try fm.copyItem(at: item, to: destItem)
        }
    }

    private let maxProjectNameLength = 64

    private func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        return name
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxProjectNameLength)
            .description
    }
}

public enum ZipImporterError: LocalizedError {
    case extractionFailed
    case unsafePath(path: String)

    public var errorDescription: String? {
        switch self {
        case .extractionFailed:
            return "Failed to extract the zip archive."
        case .unsafePath(let path):
            return "The archive contains an unsafe file path: \(path)"
        }
    }
}
