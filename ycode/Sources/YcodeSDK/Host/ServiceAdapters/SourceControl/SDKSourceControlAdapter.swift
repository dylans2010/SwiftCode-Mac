import Foundation

// MARK: - SDKSourceControlAdapter
//
// Ported from Legacy `SwiftCode/SDK/Host/ServiceAdapters/SourceControl/SDKSourceControlAdapter.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Read-only source-control access for extensions: repository status
// and diffs. Git runs directly through `Process` here and raw git
// output is parsed in this file.
//
// IMPROVEMENT over Legacy (recorded in the slice spec draft): Legacy
// routed through the app's `GitService`, whose hunk parser dropped
// `diff --git` headers and lost the first file header, forcing a
// positional `git diff --name-only` fallback (and `"unknown"` paths
// when counts mismatched). Parsing raw `git diff` output directly
// removes that quirk — paths always come from the diff headers. The
// diff path filter is likewise honored here (Legacy rejected any
// non-empty filter because its service could not honor it).

public actor SDKSourceControlAdapter {
    public static let shared = SDKSourceControlAdapter()

    /// Default diff byte budget (256 KiB).
    public static let defaultDiffByteLimit = 262_144
    public static let statusTimeout: TimeInterval = 30
    public static let diffTimeout: TimeInterval = 60

    private init() {}

    // MARK: - Repository probe (host-internal, broker-exempt)

    /// Whether `projectRoot` is inside a git work tree. Used internally
    /// by the status/diff paths; it performs no authorization itself.
    public func isRepository(projectRoot: String) async -> Bool {
        guard let git = Self.resolveGitExecutable() else { return false }
        do {
            let result = try await runGit(git, arguments: ["rev-parse", "--is-inside-work-tree"], workingDirectory: projectRoot, timeout: 10)
            return result.exitCode == 0 && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    // MARK: - Status / diff

    /// Repository status. Authorizes `.sourceControlRead` first. A
    /// non-repository returns the empty shape (`isRepository: false`),
    /// never a throw.
    public func getStatus(caller: SDKCallerIdentity) async throws -> SDKRepositoryStatus {
        try await SDKCapabilityBroker.authorize(.sourceControlRead, for: caller)
        guard let git = Self.resolveGitExecutable() else {
            throw SDKError(code: .serviceUnavailable, message: "Git is not available on this machine.")
        }
        guard await isRepository(projectRoot: caller.projectRootPath) else {
            return SDKRepositoryStatus(isRepository: false)
        }
        let result: GitResult
        do {
            result = try await runGit(git, arguments: ["status", "--porcelain=v1", "-b"], workingDirectory: caller.projectRootPath, timeout: Self.statusTimeout)
        } catch let error as SDKError {
            throw error
        } catch {
            throw SDKError(code: .serviceUnavailable, message: "Could not read the repository status.", diagnostics: ["underlyingError": String(describing: error).prefix(300).description])
        }
        guard result.exitCode == 0 else {
            throw SDKError(code: .serviceUnavailable, message: "Could not read the repository status.", diagnostics: ["gitStderr": String(result.stderr.prefix(300))])
        }
        return parseStatus(result.stdout)
    }

    /// Repository diff. Authorizes `.sourceControlRead` first. A
    /// non-repository throws `.notARepository`. The diff is byte-bounded
    /// (default 256 KiB): over-budget output sets the truncation flags,
    /// never `.outputTooLarge`.
    public func getDiff(caller: SDKCallerIdentity, options: SDKDiffOptions) async throws -> SDKRepositoryDiff {
        try await SDKCapabilityBroker.authorize(.sourceControlRead, for: caller)
        try validateDiffOptions(options)
        guard let git = Self.resolveGitExecutable() else {
            throw SDKError(code: .serviceUnavailable, message: "Git is not available on this machine.")
        }
        guard await isRepository(projectRoot: caller.projectRootPath) else {
            throw SDKError(code: .notARepository, message: "The project is not inside a source-control repository.")
        }
        let byteLimit = max(1, options.maxBytes)
        var arguments = ["diff", "--no-color"]
        if let paths = options.paths, !paths.isEmpty {
            arguments += ["--"] + paths
        }
        let result: GitResult
        do {
            result = try await runGit(git, arguments: arguments, workingDirectory: caller.projectRootPath, timeout: Self.diffTimeout)
        } catch let error as SDKError {
            throw error
        } catch {
            throw SDKError(code: .serviceUnavailable, message: "Could not read the repository diff.", diagnostics: ["underlyingError": String(describing: error).prefix(300).description])
        }
        guard result.exitCode == 0 else {
            throw SDKError(code: .serviceUnavailable, message: "Could not read the repository diff.", diagnostics: ["gitStderr": String(result.stderr.prefix(300))])
        }
        return parseDiff(result.stdout, byteLimit: byteLimit)
    }

    // MARK: - Validation

    private func validateDiffOptions(_ options: SDKDiffOptions) throws {
        guard options.maxBytes >= 1 else {
            throw SDKError(code: .invalidArgument, message: "The diff byte limit must be at least 1.")
        }
        if let paths = options.paths {
            for path in paths {
                guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("..") else {
                    throw SDKError(code: .invalidArgument, message: "Diff paths must be repository-relative and must not escape the repository.")
                }
            }
        }
        // `includeUntracked` is accepted but unsupported: `git diff`
        // has no untracked output, and inventing hunks for untracked
        // files would misrepresent the diff. Recorded in the spec draft.
    }

    // MARK: - Parsing

    private func parseStatus(_ output: String) -> SDKRepositoryStatus {
        var branchName: String?
        var ahead = 0
        var behind = 0
        var files: [SDKFileChangeSummary] = []
        var stagedCount = 0
        var unstagedCount = 0
        var untrackedCount = 0

        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if line.hasPrefix("## ") {
                // `## main...origin/main [ahead 2, behind 1]`
                let header = String(line.dropFirst(3))
                let branchPart = header.split(separator: ".", maxSplits: 1).first.map(String.init) ?? header
                branchName = branchPart.split(separator: " ").first.map(String.init)
                if let aheadRange = header.range(of: "ahead ") {
                    let rest = header[aheadRange.upperBound...]
                    ahead = Int(rest.split(separator: ",").first ?? "") ?? 0
                }
                if let behindRange = header.range(of: "behind ") {
                    let rest = header[behindRange.upperBound...]
                    behind = Int(rest.split(separator: "]").first ?? "") ?? 0
                }
                continue
            }
            guard line.count >= 4 else { continue }
            let x = line[line.startIndex]
            let y = line[line.index(line.startIndex, offsetBy: 1)]
            let path = String(line.dropFirst(3))
            let status: SDKFileChangeStatus
            switch (x, y) {
            case ("?", "?"):
                status = .untracked
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"):
                status = .conflicted
            case ("R", _), (_, "R"):
                status = .renamed
            case ("A", _):
                status = .added
            case ("D", _):
                status = .deleted
            default:
                status = .modified
            }
            let staged = x != " " && x != "?"
            if status == .untracked { untrackedCount += 1 }
            else if staged { stagedCount += 1 }
            else { unstagedCount += 1 }
            files.append(SDKFileChangeSummary(path: path, status: status, isStaged: staged))
        }

        return SDKRepositoryStatus(
            isRepository: true,
            branchName: branchName,
            ahead: ahead,
            behind: behind,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            files: files
        )
    }

    private func parseDiff(_ output: String, byteLimit: Int) -> SDKRepositoryDiff {
        var files: [SDKFileDiff] = []
        var totalBytes = 0
        var truncated = false

        // Split on `diff --git a/<path> b/<path>` headers.
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var currentPath: String?
        var currentLines: [String] = []

        func flush() {
            guard let path = currentPath else { return }
            let (hunks, isBinary) = hunksFrom(currentLines)
            let fileBytes = hunks.joined(separator: "\n").utf8.count
            if totalBytes + fileBytes > byteLimit {
                // Fit what remains of the budget, then stop.
                truncated = true
                var kept: [String] = []
                var keptBytes = 0
                for hunk in hunks {
                    let bytes = hunk.utf8.count + 1
                    if totalBytes + keptBytes + bytes > byteLimit { break }
                    kept.append(hunk)
                    keptBytes += bytes
                }
                files.append(SDKFileDiff(path: path, hunks: kept, truncated: true))
                totalBytes += keptBytes
                return
            }
            totalBytes += fileBytes
            files.append(SDKFileDiff(path: path, hunks: hunks, truncated: isBinary))
            if isBinary { truncated = true }
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
                // `diff --git a/<path> b/<path>` — the b-side is the path.
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    var path = String(parts[3])
                    if path.hasPrefix("b/") { path = String(path.dropFirst(2)) }
                    currentPath = path
                } else {
                    currentPath = nil
                }
                currentLines = []
            } else if currentPath != nil {
                currentLines.append(line)
            }
        }
        flush()

        return SDKRepositoryDiff(files: files, truncated: truncated, totalBytes: totalBytes, byteLimit: byteLimit)
    }

    /// Splits one file's diff body into hunks. Lines before the first
    /// `@@` (index/extended headers) are skipped. Binary files yield
    /// empty hunks and are flagged truncated.
    private func hunksFrom(_ lines: [String]) -> (hunks: [String], isBinary: Bool) {
        for line in lines where line.hasPrefix("Binary files ") {
            return ([], true)
        }
        var hunks: [String] = []
        var current: [String] = []
        for line in lines {
            if line.hasPrefix("@@") {
                if !current.isEmpty { hunks.append(current.joined(separator: "\n")) }
                current = [line]
            } else if !current.isEmpty {
                current.append(line)
            }
        }
        if !current.isEmpty { hunks.append(current.joined(separator: "\n")) }
        return (hunks, false)
    }

    // MARK: - Git execution

    private struct GitResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Git executable lookup: well-known locations, then every
    /// directory on `PATH`.
    static func resolveGitExecutable() -> String? {
        let candidates = [
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/usr/bin/git",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let path = "\(dir)/git"
                if FileManager.default.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// Runs git with a timeout. Stdin is /dev/null; the timeout kills
    /// the process and throws `.requestTimeout` — never a fabricated
    /// exit code.
    private func runGit(
        _ git: String,
        arguments: [String],
        workingDirectory: String,
        timeout: TimeInterval
    ) async throws -> GitResult {
        try await withThrowingTaskGroup(of: GitResult.self) { group in
            group.addTask {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: git)
                process.arguments = arguments
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
                process.standardInput = FileHandle.nullDevice
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                // Drain both pipes on their own threads so a chatty
                // child can never deadlock against a full pipe buffer.
                let stdoutTask = Task.detached { stdoutPipe.fileHandleForReading.readDataToEndOfFile() }
                let stderrTask = Task.detached { stderrPipe.fileHandleForReading.readDataToEndOfFile() }
                defer {
                    // If this task is cancelled (timeout), terminate the
                    // child so the pipe readers finish instead of leaking.
                    if process.isRunning { process.terminate() }
                }
                do {
                    try process.run()
                } catch {
                    stdoutTask.cancel()
                    stderrTask.cancel()
                    throw error
                }
                while process.isRunning {
                    try await Task.sleep(for: .milliseconds(25))
                }
                let stdout = String(data: await stdoutTask.value, encoding: .utf8) ?? ""
                let stderr = String(data: await stderrTask.value, encoding: .utf8) ?? ""
                return GitResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw SDKError(code: .requestTimeout, message: "The source-control operation timed out.")
            }
            guard let result = try await group.next() else {
                throw SDKError(code: .serviceUnavailable, message: "The source-control operation produced no result.")
            }
            group.cancelAll()
            return result
        }
    }
}
