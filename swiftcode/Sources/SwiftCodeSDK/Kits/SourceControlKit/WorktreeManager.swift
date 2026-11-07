import Foundation
import Observation
import os.log
import SwiftCodeSubprocess

private let logger = Logger(subsystem: "com.swiftcode.git", category: "WorktreeManager")

public enum WorktreeError: LocalizedError {
    case gitError(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .gitError(let message):
            return message
        case .invalidOutput(let message):
            return message
        }
    }
}

@Observable
@MainActor
public final class WorktreeManager {
    public static let shared = WorktreeManager()

    public var worktrees: [GitWorktree] = []
    public var isRefreshing = false
    public var lastError: String? = nil

    public var liveCommandLogs = ""
    public var activeProcess: Process? = nil

    public init() {}

    private var gitExecutableURL: URL {
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

    public func refresh(repositoryURL: URL) async {
        isRefreshing = true
        lastError = nil

        do {
            let listOutput = try await executeGit(args: ["worktree", "list", "--porcelain"], workingDirectory: repositoryURL)
            let parsedWorktrees = try await parsePorcelainWorktrees(listOutput, repositoryURL: repositoryURL)

            var enriched: [GitWorktree] = []
            for var wt in parsedWorktrees {
                let wtURL = URL(fileURLWithPath: wt.path)

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

                if let branchName = wt.branch {
                    if let remoteOut = try? await executeGit(args: ["rev-parse", "--abbrev-ref", "\(branchName)@{upstream}"], workingDirectory: wtURL) {
                        wt.remoteBranch = remoteOut.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                if let statusOut = try? await executeGit(args: ["status", "--porcelain"], workingDirectory: wtURL) {
                    let lines = statusOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    wt.modifiedCount = lines.filter { $0.hasPrefix(" M") || $0.hasPrefix("M ") }.count
                    wt.stagedCount = lines.filter { $0.hasPrefix("A ") || $0.hasPrefix("M ") || $0.hasPrefix("D ") }.count
                    wt.untrackedCount = lines.filter { $0.hasPrefix("??") }.count
                    wt.isDirty = !lines.isEmpty
                }

                if let abOut = try? await executeGit(args: ["rev-list", "--left-right", "--count", "HEAD...@{u}"], workingDirectory: wtURL) {
                    let parts = abOut.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
                    if parts.count == 2, let ahead = Int(parts[0]), let behind = Int(parts[1]) {
                        wt.aheadCount = ahead
                        wt.behindCount = behind
                    }
                }

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

        guard let wt = worktrees.first(where: { $0.path == sourcePath }), let branch = wt.branch else {
            throw WorktreeError.gitError("Cannot duplicate a detached HEAD or missing worktree.")
        }

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

    private func executeGit(args: [String], workingDirectory: URL) async throws -> String {
        let executable = gitExecutableURL.path
        let output = try await Task.detached {
            try Subprocess.run(executable, args, currentDirectory: workingDirectory)
        }.value
        guard output.status == 0 else {
            throw WorktreeError.gitError(output.stderrText.isEmpty ? output.stdoutText : output.stderrText)
        }
        return output.stdoutText
    }

    public func cancelActiveProcess() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
            appendLogStream("\n[Operation cancelled by user]\n")
        }
        activeProcess = nil
    }

    private func executeGitStreaming(args: [String], workingDirectory: URL) async throws -> Bool {
        liveCommandLogs = "❯ git \(args.joined(separator: " "))\n"

        let proc = Process()
        proc.executableURL = gitExecutableURL
        proc.arguments = args
        proc.currentDirectoryURL = workingDirectory
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLogStream(line)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLogStream(line)
            }
        }

        do {
            try proc.run()
        } catch {
            throw WorktreeError.gitError(error.localizedDescription)
        }

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

    private func parsePorcelainWorktrees(_ porcelain: String, repositoryURL: URL) async throws -> [GitWorktree] {
        var parsed: [GitWorktree] = []
        let lines = porcelain.components(separatedBy: .newlines)

        var currentPath = ""
        var currentSHA = ""
        var currentBranch = ""
        var isLocked = false
        var lockReason = ""

        func finishCurrent() {
            guard !currentPath.isEmpty else { return }
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

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("worktree ") {
                finishCurrent()

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

        finishCurrent()

        return parsed
    }

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
