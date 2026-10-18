import Foundation

public enum AssistToolingSupport {
    /// Resolves a workspace-relative path. Never escapes the workspace root:
    /// a path that would escape (via `..` or an absolute path) is clamped to
    /// the root instead of silently pointing outside it. Callers that need a
    /// hard failure on escape should use `AssistFileSystem.resolve` instead.
    public static func resolvePath(_ path: String?, workspaceRoot: URL) -> URL {
        let rawPath = (path?.isEmpty == false ? path! : ".")
        if rawPath == "." { return workspaceRoot }
        let root = workspaceRoot.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = workspaceRoot.appendingPathComponent(rawPath).standardized
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            return workspaceRoot
        }
        return resolved
    }

    public static func relativePath(for url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.path
        if url.path.hasPrefix(root + "/") {
            return String(url.path.dropFirst(root.count + 1))
        }
        return url.lastPathComponent
    }

    public static func enumeratedFiles(at root: URL, allowedExtensions: Set<String>? = nil, maxFileSize: Int = 300_000) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else {
                continue
            }
            if let size = values.fileSize, size > maxFileSize { continue }
            if let allowedExtensions {
                let ext = fileURL.pathExtension.lowercased()
                if !allowedExtensions.contains(ext) { continue }
            }
            files.append(fileURL)
        }
        return files
    }

    public static func isCodeFile(_ fileURL: URL) -> Bool {
        let codeExtensions: Set<String> = ["swift", "m", "mm", "h", "hpp", "c", "cpp", "js", "ts", "tsx", "jsx", "py", "rb", "java", "kt", "go", "rs"]
        return codeExtensions.contains(fileURL.pathExtension.lowercased())
    }

    public static func readText(_ url: URL) -> String? {
        return try? String(contentsOf: url, encoding: .utf8)
    }

    public static func keywordOccurrences(in content: String, keywords: [String]) -> Int {
        keywords.reduce(0) { partial, keyword in
            partial + content.components(separatedBy: keyword).count - 1
        }
    }
}

/// Argument-vector process runner for Assist tools.
///
/// Model-supplied values must NEVER be interpolated into a shell command
/// string (`/bin/bash -lc "xcodebuild … \(scheme)"` lets a crafted scheme
/// execute arbitrary shell). Pass argv arrays here instead: `Process`
/// executes the binary directly with no shell, so metacharacters in an
/// argument are inert. Runs are bounded: on timeout the process gets
/// SIGTERM, then SIGKILL after a short grace period, and the call returns
/// `timedOut: true` instead of hanging forever.
public enum AssistArgvRunner {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let output: String
        public let timedOut: Bool
    }

    public static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeout: TimeInterval = 300
    ) throws -> Result {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        let waitResult = semaphore.wait(timeout: .now() + timeout)
        var timedOut = false
        if waitResult == .timedOut {
            timedOut = true
            process.terminate() // SIGTERM
            if semaphore.wait(timeout: .now() + 5) == .timedOut {
                // SIGKILL: Process has no kill(); use the POSIX call.
                kill(process.processIdentifier, SIGKILL)
                _ = semaphore.wait(timeout: .now() + 5)
            }
        }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(exitCode: process.terminationStatus, output: output, timedOut: timedOut)
    }
}
