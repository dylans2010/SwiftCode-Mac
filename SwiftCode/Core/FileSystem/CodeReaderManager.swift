import Foundation

/// Dedicated manager for reading project files from disk and delivering their contents to the code editor.
///
/// All file reads are resolved relative to the project root inside the Projects directory:
///   Documents/Projects/{projectName}/{relativePath}
///
/// The editor must always read files through CodeReaderManager so that file paths are
/// resolved correctly regardless of how they were originally stored (e.g., after ZIP import).
final class CodeReaderManager {
    static let shared = CodeReaderManager()
    private init() {}

    private let fm = FileManager.default

    // MARK: - Projects Directory

    private var projectsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects")
    }

    /// Builds the absolute URL for a file inside a project.
    func fileURL(project: String, relativePath: String) -> URL {
        projectsURL
            .appendingPathComponent(project)
            .appendingPathComponent(relativePath)
    }

    // MARK: - Synchronous Read

    /// Read a file from the given project using its relative path.
    ///
    /// Path resolution: Documents/Projects/{project}/{relativePath}
    func readFile(project: String, relativePath: String) throws -> String {
        let url = fileURL(project: project, relativePath: relativePath)

        guard fm.fileExists(atPath: url.path) else {
            throw CodeReaderError.fileNotFound(path: url.path)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Asynchronous Read (for large files)

    /// Asynchronously read a file from the given project.
    /// Supports large files without blocking the main thread.
    /// Automatically retries once if the file is temporarily unavailable (e.g., during indexing).
    func readFileAsync(project: String, relativePath: String, retryCount: Int = 1) async throws -> String {
        let url = fileURL(project: project, relativePath: relativePath)

        for attempt in 0...retryCount {
            // Check for cancellation before each attempt
            try Task.checkCancellation()

            if fm.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    guard let content = String(data: data, encoding: .utf8) else {
                        throw CodeReaderError.encodingFailed(path: url.path)
                    }
                    return content
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if attempt < retryCount {
                        // Brief pause before retry — allows indexing to complete
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
                        continue
                    }
                    throw error
                }
            } else if attempt < retryCount {
                // File may not be visible yet — wait and retry
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 s
            }
        }

        throw CodeReaderError.fileNotFound(path: url.path)
    }

    // MARK: - File Existence

    func fileExists(project: String, relativePath: String) -> Bool {
        fm.fileExists(atPath: fileURL(project: project, relativePath: relativePath).path)
    }

    // MARK: - Project Scan

    /// Scan all files inside a project and return their relative paths.
    /// Suitable for building or rebuilding the file navigator after ZIP import.
    func scanProjectFiles(projectName: String) -> [String] {
        let projectDir = projectsURL.appendingPathComponent(projectName)
        var result: [String] = []

        guard let enumerator = fm.enumerator(
            at: projectDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        let base = projectDir.standardizedFileURL.path

        while let url = enumerator.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }

            let childPath = url.standardizedFileURL.path
            guard childPath.hasPrefix(base + "/") else { continue }
            let rel = String(childPath.dropFirst(base.count + 1))
            if !rel.isEmpty, rel != "project.json" {
                result.append(rel)
            }
        }

        return result.sorted()
    }
}

// MARK: - Errors

enum CodeReaderError: LocalizedError {
    case fileNotFound(path: String)
    case encodingFailed(path: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File does not exist at path: \(path)"
        case .encodingFailed(let path):
            return "Failed to decode file as UTF-8: \(path)"
        }
    }
}
