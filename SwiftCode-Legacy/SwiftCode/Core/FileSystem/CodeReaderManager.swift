import Foundation

final class CodeReaderManager: Sendable {
    static let shared = CodeReaderManager()
    private init() {}

    private var fm: FileManager { .default }

    private var projectsURL: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects")
    }

    func fileURL(project: String, relativePath: String) -> URL {
        projectsURL
            .appendingPathComponent(project)
            .appendingPathComponent(relativePath)
    }

    func readFile(project: String, relativePath: String) throws -> String {
        let url = fileURL(project: project, relativePath: relativePath)

        guard fm.fileExists(atPath: url.path) else {
            throw CodeReaderError.fileNotFound(path: url.path)
        }

        return try String(contentsOf: url, encoding: .utf8)
    }

    func readFileAsync(project: String, relativePath: String, retryCount: Int = 1) async throws -> String {
        let url = fileURL(project: project, relativePath: relativePath)

        for attempt in 0...retryCount {
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
                        try await Task.sleep(nanoseconds: 500_000_000)
                        continue
                    }
                    throw error
                }
            } else if attempt < retryCount {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        throw CodeReaderError.fileNotFound(path: url.path)
    }

    func fileExists(project: String, relativePath: String) -> Bool {
        fm.fileExists(atPath: fileURL(project: project, relativePath: relativePath).path)
    }

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
