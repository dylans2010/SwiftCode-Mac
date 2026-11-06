// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/ZipImporter.swift
// Adapted for Ycode: URL-based instead of Project-based: export zips a project directory, import extracts a zip into a fresh directory and returns its name + URL. ZIPFoundation is not a Ycode dependency, so extraction uses the same tools YcodeExtensions' PackageService uses: /usr/bin/ditto -x -k on macOS, /usr/bin/unzip on Linux (export: ditto -c -k / `zip -r`). Legacy's FileNode tree building and project.json metadata are dropped — Ycode discovers the file tree itself and has no .scproj/project.json format. Path-traversal validation is kept verbatim.

import Foundation

/// The result of importing a zip: the project name and the directory its
/// contents were extracted into. The caller (the NewProject flow / workspace
/// opener) decides what to do with it.
public struct ImportedProjectDirectory: Sendable {
    public let name: String
    public let directoryURL: URL

    public init(name: String, directoryURL: URL) {
        self.name = name
        self.directoryURL = directoryURL
    }
}

/// Imports and exports project directories as `.zip` archives.
public final class ProjectZipImporter: Sendable {
    public static let shared = ProjectZipImporter()
    private init() {}

    // MARK: - Export

    /// Exports a project directory as a `.zip` file and returns the local URL.
    public func exportZip(projectURL: URL, projectName: String) async throws -> URL {
        let fm = FileManager.default
        let zipName = "\(projectName).zip"
        let destURL = fm.temporaryDirectory.appendingPathComponent(zipName)
        // Remove old export if present
        try? fm.removeItem(at: destURL)
        try zipDirectory(projectURL, to: destURL)
        return destURL
    }

    // MARK: - Import

    /// Imports a zip file, creating a new project directory with the
    /// extracted contents. The destination is `baseDirectory` (default:
    /// ~/Documents/SwiftCode Projects); name collisions get a numeric suffix.
    public func importZip(at zipURL: URL, into baseDirectory: URL? = nil) async throws -> ImportedProjectDirectory {
        let fm = FileManager.default
        let projectName = zipURL.deletingPathExtension().lastPathComponent
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer { try? fm.removeItem(at: tempDir) }

        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try unzip(zipURL, to: tempDir)

        let extractedRoot = try findExtractedRoot(in: tempDir)
        let sanitized = sanitizeName(projectName)

        // Build destination project directory, handling name collisions.
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

    // MARK: - Zip / Unzip (ditto on macOS, zip/unzip on Linux)

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
        // `zip -r <archive> .` zips the current directory, so run it with
        // the project directory as the working directory.
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

    // MARK: - Find Root

    /// If the zip contains a single top-level directory, return it; otherwise return the temp dir itself.
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

    // MARK: - Copy Contents with Path Validation

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

            // Validate: prevent directory traversal attacks.
            guard !itemName.contains(".."), !itemName.hasPrefix("/") else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            let destItem = destination.appendingPathComponent(itemName)

            // Ensure destination stays inside the project directory.
            guard destItem.path.hasPrefix(destination.path) else {
                throw ZipImporterError.unsafePath(path: itemName)
            }

            try fm.copyItem(at: item, to: destItem)
        }
    }

    // MARK: - Helpers

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

// MARK: - Errors

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
