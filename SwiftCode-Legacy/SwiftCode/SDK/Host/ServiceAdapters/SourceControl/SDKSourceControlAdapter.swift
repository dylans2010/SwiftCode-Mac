import Foundation

public actor SDKSourceControlAdapter {

    public static let shared = SDKSourceControlAdapter()

    private init() {}

    public func isRepository(at projectRoot: URL) async -> Bool {
        guard let result = try? await ProcessRunnerTool.shared.run(
            executableURL: await gitExecutableURL(),
            arguments: ["rev-parse", "--is-inside-work-tree"],
            workingDirectory: projectRoot
        ) else {
            return false
        }
        return result.exitCode == 0
            && result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    public func getStatus(caller: SDKCallerIdentity) async throws -> SDKRepositoryStatus {
        try await SDKCapabilityBroker.authorize(.sourceControlRead, for: caller)

        let projectRoot = URL(
            fileURLWithPath: caller.projectRootPath,
            isDirectory: true
        ).standardized

        guard await isRepository(at: projectRoot) else {
            return SDKRepositoryStatus(isRepository: false)
        }

        do {
            let snapshot = try await withTimeout(seconds: 30) {
                try await GitService.shared.getStatus(for: projectRoot)
            }
            return mapStatus(snapshot, root: projectRoot)
        } catch let appError as AppError {
            throw mapGitError(appError)
        }
    }

    public func getDiff(
        caller: SDKCallerIdentity,
        options: SDKDiffOptions
    ) async throws -> SDKRepositoryDiff {
        try await SDKCapabilityBroker.authorize(.sourceControlRead, for: caller)

        let projectRoot = URL(
            fileURLWithPath: caller.projectRootPath,
            isDirectory: true
        ).standardized

        try validateDiffPaths(options.paths)

        do {
            let (hunks, pathOrder) = try await withTimeout(seconds: 60) {
                async let diffHunks = GitService.shared.getDiff(repositoryURL: projectRoot)
                async let nameOrder = self.diffPathOrder(root: projectRoot)
                return try await (diffHunks, nameOrder)
            }
            return assembleDiff(from: hunks, maxBytes: options.maxBytes, pathOrderFallback: pathOrder)
        } catch let appError as AppError {
            throw mapGitError(appError)
        }
    }

    private func mapStatus(_ snapshot: GitStatusSnapshot, root: URL) -> SDKRepositoryStatus {
        let files = snapshot.files.map { file in
            SDKFileChangeSummary(
                path: repoRelativePath(file.path, root: root),
                status: mapFileStatus(file.status),
                isStaged: file.isStaged
            )
        }
        let stagedCount = snapshot.files.filter { $0.isStaged }.count
        let untrackedCount = snapshot.files.filter { $0.status == .untracked }.count
        let unstagedCount = snapshot.files.filter {
            !$0.isStaged && $0.status != .untracked
        }.count

        let rawBranch = snapshot.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchName: String? =
            (rawBranch.isEmpty || rawBranch.caseInsensitiveCompare("unknown") == .orderedSame)
            ? nil : rawBranch

        return SDKRepositoryStatus(
            isRepository: true,
            branchName: branchName,
            ahead: snapshot.ahead,
            behind: snapshot.behind,
            stagedCount: stagedCount,
            unstagedCount: unstagedCount,
            untrackedCount: untrackedCount,
            files: files
        )
    }

    private func mapFileStatus(_ status: GitFileStatus.Status) -> SDKFileChangeStatus {
        switch status {
        case .modified: return .modified
        case .added: return .added
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .untracked: return .untracked
        case .conflicted: return .conflicted
        }
    }

    private func repoRelativePath(_ fileURL: URL, root: URL) -> String {
        let rootPath = root.path
        let path = fileURL.standardized.path
        if path == rootPath {
            return fileURL.lastPathComponent
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    private struct RawFileDiff {
        var path: String
        var chunks: [String] = []
        var isBinary = false
    }

    private func assembleDiff(
        from hunks: [GitDiffHunk],
        maxBytes: Int,
        pathOrderFallback: [String]
    ) -> SDKRepositoryDiff {
        var rawFiles: [RawFileDiff] = []
        var current: RawFileDiff? = nil
        func flush() {
            if let file = current { rawFiles.append(file) }
            current = nil
        }
        for hunk in hunks {
            for line in [hunk.header] + hunk.lines {
                if line.hasPrefix("diff --git ") {
                    flush()
                    current = RawFileDiff(path: parseDiffGitPath(line) ?? "unknown")
                } else if line.hasPrefix("Binary files ") {
                    if current == nil { current = RawFileDiff(path: "unknown") }
                    current?.isBinary = true
                } else {
                    if current == nil { current = RawFileDiff(path: "unknown") }
                    current?.chunks.append(line)
                }
            }
        }
        flush()

        if pathOrderFallback.count == rawFiles.count {
            for index in rawFiles.indices where rawFiles[index].path == "unknown" {
                rawFiles[index].path = pathOrderFallback[index]
            }
        }

        struct BuiltFile {
            let path: String
            let hunkTexts: [String]
            let isBinary: Bool
            let byteCount: Int
        }
        let built: [BuiltFile] = rawFiles.map { raw in
            if raw.isBinary {
                return BuiltFile(path: raw.path, hunkTexts: [], isBinary: true, byteCount: 0)
            }
            var hunkTexts: [String] = []
            var pending: [String] = []
            for line in raw.chunks {
                if line.hasPrefix("@@ ") && !pending.isEmpty {
                    hunkTexts.append(pending.joined(separator: "\n"))
                    pending = []
                }
                pending.append(line)
            }
            if !pending.isEmpty {
                hunkTexts.append(pending.joined(separator: "\n"))
            }
            let byteCount = hunkTexts.reduce(0) { $0 + $1.utf8.count }
            return BuiltFile(path: raw.path, hunkTexts: hunkTexts, isBinary: false, byteCount: byteCount)
        }

        let totalBytes = built.reduce(0) { $0 + $1.byteCount }

        var emitted: [SDKFileDiff] = []
        var usedBytes = 0
        var truncated = false
        for file in built {
            if usedBytes + file.byteCount <= maxBytes {
                emitted.append(SDKFileDiff(
                    path: file.path,
                    hunks: file.hunkTexts,
                    truncated: file.isBinary
                ))
                usedBytes += file.byteCount
                if file.isBinary { truncated = true }
                continue
            }
            var kept: [String] = []
            var keptBytes = 0
            for hunkText in file.hunkTexts {
                let remaining = maxBytes - usedBytes - keptBytes
                guard remaining > 0 else { break }
                let hunkBytes = hunkText.utf8.count
                if keptBytes + hunkBytes <= remaining {
                    kept.append(hunkText)
                    keptBytes += hunkBytes
                } else {
                    let piece = bytePrefix(hunkText, limit: remaining - keptBytes)
                    if !piece.isEmpty {
                        kept.append(piece)
                        keptBytes += piece.utf8.count
                    }
                    break
                }
            }
            emitted.append(SDKFileDiff(path: file.path, hunks: kept, truncated: true))
            usedBytes += keptBytes
            truncated = true
            break
        }

        return SDKRepositoryDiff(
            files: emitted,
            truncated: truncated,
            totalBytes: totalBytes,
            byteLimit: maxBytes
        )
    }

    private func parseDiffGitPath(_ line: String) -> String? {
        let rest = String(line.dropFirst("diff --git ".count))
        if let range = rest.range(of: " b/", options: .backwards) {
            var path = String(rest[range.upperBound...])
            if path.hasPrefix("\"") && path.hasSuffix("\"") && path.count >= 2 {
                path = String(path.dropFirst().dropLast())
            }
            return path.isEmpty ? nil : path
        }
        if let token = rest.split(separator: " ").last.map(String.init) {
            let stripped = token.hasPrefix("b/") ? String(token.dropFirst(2)) : token
            return stripped.isEmpty ? nil : stripped
        }
        return nil
    }

    private func bytePrefix(_ text: String, limit: Int) -> String {
        guard limit > 0 else { return "" }
        var bytes = 0
        var result = ""
        result.reserveCapacity(min(limit, text.utf8.count))
        for character in text {
            let charBytes = String(character).utf8.count
            if bytes + charBytes > limit { break }
            bytes += charBytes
            result.append(character)
        }
        return result
    }

    private func validateDiffPaths(_ paths: [String]?) throws {
        guard let paths, !paths.isEmpty else { return }
        for path in paths {
            if path.hasPrefix("/") || path.split(separator: "/").contains("..") {
                throw SDKError(
                    code: .invalidArgument,
                    message: "Diff path filters must be repository-relative paths without '..' segments.",
                    suggestion: "Pass paths like \"Sources/App.swift\"."
                )
            }
        }
        throw SDKError(
            code: .invalidArgument,
            message: "Path-filtered diffs are not supported by the host yet.",
            suggestion: "Omit the paths filter to diff the whole repository."
        )
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw SDKError(
                    code: .requestTimeout,
                    message: "The source-control request took longer than \(seconds) seconds.",
                    suggestion: "Try again; the repository may be unusually large or busy."
                )
            }
            guard let result = try await group.next() else {
                throw SDKError(
                    code: .requestTimeout,
                    message: "The source-control request produced no result.",
                    suggestion: "Try again."
                )
            }
            group.cancelAll()
            return result
        }
    }

    private func mapGitError(_ error: AppError) -> SDKError {
        guard case .gitError(let stderr) = error else {
            return SDKError(
                code: .serviceUnavailable,
                message: "Source control is temporarily unavailable.",
                suggestion: "Try again in a moment."
            )
        }
        let lowered = stderr.lowercased()

        if lowered.contains("not a git repository") {
            return SDKError(
                code: .notARepository,
                message: "This project is not inside a git repository.",
                suggestion: "Open a project that lives inside a git repository to use source-control features."
            )
        }

        let sanitized = String(
            SDKLogRedaction.sanitizeForUser(stderr).prefix(300)
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if lowered.contains("permission denied") {
            return SDKError(
                code: .serviceUnavailable,
                message: "Source control hit a host filesystem permission problem (not an extension-permission problem).",
                suggestion: "Check that SwiftCode can read the repository directory, then try again.",
                diagnostics: sanitized.isEmpty ? nil : ["detail": sanitized]
            )
        }

        let message = sanitized.isEmpty
            ? "Git reported an error."
            : "Git reported an error: \(sanitized)"
        return SDKError(
            code: .serviceUnavailable,
            message: message,
            suggestion: "Try again; if it persists, check the repository in a terminal."
        )
    }

    private nonisolated func diffPathOrder(root: URL) async -> [String] {
        guard let result = try? await ProcessRunnerTool.shared.run(
            executableURL: await self.gitExecutableURL(),
            arguments: ["diff", "--name-only"],
            workingDirectory: root
        ), result.exitCode == 0 else {
            return []
        }
        return result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { path in
                var p = path
                if p.hasPrefix("\"") && p.hasSuffix("\"") && p.count >= 2 {
                    p = String(p.dropFirst().dropLast())
                }
                return p
            }
    }

    private func gitExecutableURL() async -> URL {
        if let customPath = await PreferencesStore.shared.get(forKey: "git_executable_path") as? String,
           !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        let commonPaths = [
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git",
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/usr/bin/git"
        ]
        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }
}
