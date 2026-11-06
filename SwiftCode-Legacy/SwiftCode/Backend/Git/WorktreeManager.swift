import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.git", category: "WorktreeManager")

@Observable
@MainActor
public final class WorktreeManager {
    public static let shared = WorktreeManager()

    public var worktrees: [GitWorktree] = []
    public var isRefreshing = false
    public var lastError: String? = nil

    // Live execution log stream for the UI
    public var liveCommandLogs = ""
    public var activeProcess: Process? = nil

    private init() {}

    // MARK: - API / Command Exporter

    private var gitExecutableURL: URL {
        // Fallback to common paths if preference not found
        if let customPath = UserDefaults.standard.string(forKey: "git_executable_path"), !customPath.isEmpty {
            return URL(fileURLWithPath: customPath)
        }
        for path in ["/usr/local/bin/git", "/opt/homebrew/bin/git", "/usr/bin/git"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/git")
    }

    // MARK: - Query State

    public func refresh(repositoryURL: URL) async {
        isRefreshing = true
        lastError = nil

        do {
            let listOutput = try await executeGit(args: ["worktree", "list", "--porcelain"], workingDirectory: repositoryURL)
            let parsedWorktrees = try await parsePorcelainWorktrees(listOutput, repositoryURL: repositoryURL)

            // Enrich with detailed repository details & user options
            var enriched: [GitWorktree] = []
            for var wt in parsedWorktrees {
                let wtURL = URL(fileURLWithPath: wt.path)

                // Get Commit Details
                if let logOut = try? await executeGit(args: ["log", "-1", "--pretty=format:%s|%an|%at"], workingDirectory: wtURL) {
                    let parts = logOut.components(separatedBy: "|")
                    if parts.count >= 3 {
                        wt.commitMessage = parts[0]
                        wt.commitAuthor = parts[1]
                        if let timeInterval = Double(parts[2]) {
                            wt.commitDate = Date(timeIntervalSince1970: timeInterval)
                        }
                    }
                }

                // Get Remote Upstream Tracking Branch
                if let branchName = wt.branch {
                    if let remoteOut = try? await executeGit(args: ["rev-parse", "--abbrev-ref", "\(branchName)@{upstream}"], workingDirectory: wtURL) {
                        wt.remoteBranch = remoteOut.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                // Get Dirty Counts & File Status
                if let statusOut = try? await executeGit(args: ["status", "--porcelain"], workingDirectory: wtURL) {
                    let lines = statusOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    wt.modifiedCount = lines.filter { $0.hasPrefix(" M") || $0.hasPrefix("M ") }.count
                    wt.stagedCount = lines.filter { $0.hasPrefix("A ") || $0.hasPrefix("M ") || $0.hasPrefix("D ") }.count
                    wt.untrackedCount = lines.filter { $0.hasPrefix("??") }.count
                    wt.isDirty = !lines.isEmpty
                }

                // Get Ahead / Behind Counts
                if let abOut = try? await executeGit(args: ["rev-list", "--left-right", "--count", "HEAD...@{u}"], workingDirectory: wtURL) {
                    let parts = abOut.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
                    if parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) {
                        wt.aheadCount = ahead
                        wt.behindCount = behind
                    }
                }

                // Get Persistent preferences
                wt.isFavorite = UserDefaults.standard.bool(forKey: "wt_fav_\(wt.path)")
                wt.isPinned = UserDefaults.standard.bool(forKey: "wt_pin_\(wt.path)")
                if let interval = UserDefaults.standard.object(forKey: "wt_opened_\(wt.path)") as? Double {
                    wt.lastOpenedDate = Date(timeIntervalSince1970: interval)
                }

                wt.repositoryName = repositoryURL.lastPathComponent

                enriched.append(wt)
            }

            self.worktrees = enriched
        } catch {
            logger.error("Failed to query worktrees: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
        }

        isRefreshing = false
    }

    // MARK: - Lifecycle Management

    public func createWorktree(at path: String, branch: String, fromExisting: Bool, isNewBranch: Bool, repositoryURL: URL) async throws {
        appendLogStream("Initializing Worktree creation request...\nPath: \(path)\nBranch: \(branch)\n")

        var args = ["worktree", "add"]
        if isNewBranch {
            args.append("-b")
            args.append(branch)
            args.append(path)
        } else {
            args.append(path)
            if fromExisting {
                args.append(branch)
            }
        }

        _ = try await executeGitStreaming(args: args, workingDirectory: repositoryURL)
        appendLogStream("✓ Worktree successfully created.\n")
        await refresh(repositoryURL: repositoryURL)
    }

    public func duplicateWorktree(sourcePath: String, destinationPath: String, repositoryURL: URL) async throws {
        appendLogStream("Duplicating Worktree structure from \(sourcePath) to \(destinationPath)\n")

        // Find existing worktree branch
        guard let wt = worktrees.first(where: { $0.path == sourcePath }), let branch = wt.branch else {
            throw AppError.gitError("Cannot duplicate a detached HEAD or missing worktree.")
        }

        // Generate a duplicate branch name or same branch
        let dupBranchName = "\(branch)-copy-\(Int(Date().timeIntervalSince1970) % 10000)"
        try await createWorktree(at: destinationPath, branch: dupBranchName, fromExisting: true, isNewBranch: true, repositoryURL: repositoryURL)
    }

    public func renameWorktree(worktreePath: String, newName: String, repositoryURL: URL) async throws {
        let parentDir = (worktreePath as NSString).deletingLastPathComponent
        let newPath = (parentDir as NSString).appendingPathComponent(newName)
        try await moveWorktree(worktreePath: worktreePath, destinationPath: newPath, repositoryURL: repositoryURL)
    }

    public func moveWorktree(worktreePath: String, destinationPath: String, repositoryURL: URL) async throws {
        appendLogStream("Moving worktree from \(worktreePath) to \(destinationPath)...\n")
        _ = try await executeGitStreaming(args: ["worktree", "move", worktreePath, destinationPath], workingDirectory: repositoryURL)
        appendLogStream("✓ Worktree moved successfully.\n")
        await refresh(repositoryURL: repositoryURL)
    }

    public func removeWorktree(worktreePath: String, force: Bool, repositoryURL: URL) async throws {
        appendLogStream("Removing worktree at \(worktreePath) (Force: \(force))...\n")
        var args = ["worktree", "remove", worktreePath]
        if force { args.append("--force") }
        _ = try await executeGitStreaming(args: args, workingDirectory: repositoryURL)
        appendLogStream("✓ Worktree removed.\n")

        // Clean persistent keys
        UserDefaults.standard.removeObject(forKey: "wt_fav_\(worktreePath)")
        UserDefaults.standard.removeObject(forKey: "wt_pin_\(worktreePath)")
        UserDefaults.standard.removeObject(forKey: "wt_opened_\(worktreePath)")

        await refresh(repositoryURL: repositoryURL)
    }

    public func lockWorktree(worktreePath: String, reason: String, repositoryURL: URL) async throws {
        appendLogStream("Locking worktree at \(worktreePath) for reason: \(reason)...\n")
        _ = try await executeGitStreaming(args: ["worktree", "lock", worktreePath, "--reason", reason], workingDirectory: repositoryURL)
        appendLogStream("✓ Worktree locked.\n")
        await refresh(repositoryURL: repositoryURL)
    }

    public func unlockWorktree(worktreePath: String, repositoryURL: URL) async throws {
        appendLogStream("Unlocking worktree at \(worktreePath)...\n")
        _ = try await executeGitStreaming(args: ["worktree", "unlock", worktreePath], workingDirectory: repositoryURL)
        appendLogStream("✓ Worktree unlocked.\n")
        await refresh(repositoryURL: repositoryURL)
    }

    public func repairWorktree(repositoryURL: URL) async throws {
        appendLogStream("Repairing worktree structures...\n")
        _ = try await executeGitStreaming(args: ["worktree", "repair"], workingDirectory: repositoryURL)
        appendLogStream("✓ Worktree structures repaired.\n")
        await refresh(repositoryURL: repositoryURL)
    }

    public func pruneWorktrees(repositoryURL: URL) async throws {
        appendLogStream("Pruning stale worktrees...\n")
        _ = try await executeGitStreaming(args: ["worktree", "prune"], workingDirectory: repositoryURL)
        appendLogStream("✓ Stale worktree records pruned.\n")
        await refresh(repositoryURL: repositoryURL)
    }

    // MARK: - Synchronous Execution Helpers

    private func executeGit(args: [String], workingDirectory: URL) async throws -> String {
        let runner = ProcessRunnerTool.shared
        let result = try await runner.run(
            executableURL: gitExecutableURL,
            arguments: args,
            workingDirectory: workingDirectory
        )
        guard result.exitCode == 0 else {
            throw AppError.gitError(result.stderr)
        }
        return result.stdout
    }

    // MARK: - Streaming / Cancellable Execution Helpers

    public func cancelActiveProcess() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
            appendLogStream("\n[Operation cancelled by user]\n")
        }
        activeProcess = nil
    }

    private func executeGitStreaming(args: [String], workingDirectory: URL) async throws -> Bool {
        liveCommandLogs = "❯ git \(args.joined(separator: " "))\n"

        let runner = ProcessRunnerTool.shared
        let proc = try runner.runStreaming(
            executableURL: gitExecutableURL,
            arguments: args,
            workingDirectory: workingDirectory,
            onStdout: { [weak self] line in
                Task { @MainActor in
                    self?.appendLogStream(line)
                }
            },
            onStderr: { [weak self] line in
                Task { @MainActor in
                    self?.appendLogStream(line)
                }
            }
        )

        self.activeProcess = proc

        return await withCheckedContinuation { continuation in
            proc.terminationHandler = { [weak self] p in
                Task { @MainActor in
                    self?.activeProcess = nil
                    continuation.resume(returning: p.terminationStatus == 0)
                }
            }
            if !proc.isRunning {
                self.activeProcess = nil
                continuation.resume(returning: proc.terminationStatus == 0)
            }
        }
    }

    private func appendLogStream(_ str: String) {
        liveCommandLogs += str
    }

    // MARK: - Porcelain Output Parser

    private func parsePorcelainWorktrees(_ porcelain: String, repositoryURL: URL) async throws -> [GitWorktree] {
        var parsed: [GitWorktree] = []
        let lines = porcelain.components(separatedBy: .newlines)

        var currentPath = ""
        var currentSHA = ""
        var currentBranch = ""
        var isLocked = false
        var lockReason = ""

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("worktree ") {
                if !currentPath.isEmpty {
                    let cleanedBranch = currentBranch.hasPrefix("refs/heads/") ? String(currentBranch.dropFirst("refs/heads/".count)) : (currentBranch.isEmpty ? nil : currentBranch)
                    let wt = GitWorktree(
                        path: currentPath,
                        headSHA: currentSHA,
                        branch: cleanedBranch,
                        isMain: currentPath == repositoryURL.path,
                        isLocked: isLocked,
                        lockReason: isLocked ? (lockReason.isEmpty ? "No reason specified" : lockReason) : nil
                    )
                    parsed.append(wt)
                }

                // Reset state
                currentPath = line.replacingOccurrences(of: "worktree ", with: "").trimmingCharacters(in: .whitespaces)
                currentSHA = ""
                currentBranch = ""
                isLocked = false
                lockReason = ""
            } else if line.hasPrefix("HEAD ") {
                currentSHA = line.replacingOccurrences(of: "HEAD ", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("branch ") {
                currentBranch = line.replacingOccurrences(of: "branch ", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("locked") {
                isLocked = true
                lockReason = line.replacingOccurrences(of: "locked", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        // Append last
        if !currentPath.isEmpty {
            let cleanedBranch = currentBranch.hasPrefix("refs/heads/") ? String(currentBranch.dropFirst("refs/heads/".count)) : (currentBranch.isEmpty ? nil : currentBranch)
            let wt = GitWorktree(
                path: currentPath,
                headSHA: currentSHA,
                branch: cleanedBranch,
                isMain: currentPath == repositoryURL.path,
                isLocked: isLocked,
                lockReason: isLocked ? (lockReason.isEmpty ? "No reason specified" : lockReason) : nil
            )
            parsed.append(wt)
        }

        return parsed
    }

    // MARK: - Options Actions

    public func toggleFavorite(for worktree: GitWorktree) {
        let key = "wt_fav_\(worktree.path)"
        let val = !worktree.isFavorite
        UserDefaults.standard.set(val, forKey: key)
        if let idx = worktrees.firstIndex(where: { $0.path == worktree.path }) {
            worktrees[idx].isFavorite = val
        }
    }

    public func togglePinned(for worktree: GitWorktree) {
        let key = "wt_pin_\(worktree.path)"
        let val = !worktree.isPinned
        UserDefaults.standard.set(val, forKey: key)
        if let idx = worktrees.firstIndex(where: { $0.path == worktree.path }) {
            worktrees[idx].isPinned = val
        }
    }

    public func updateLastOpened(for worktree: GitWorktree) {
        let key = "wt_opened_\(worktree.path)"
        let date = Date()
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
        if let idx = worktrees.firstIndex(where: { $0.path == worktree.path }) {
            worktrees[idx].lastOpenedDate = date
        }
    }
}
