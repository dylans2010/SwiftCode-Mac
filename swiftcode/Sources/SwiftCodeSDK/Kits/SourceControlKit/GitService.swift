// Ported from SwiftCode-Legacy `SwiftCode/Backend/Git/GitService.swift` (Dylan's own code; direct port authorised under MIT).
// V10 (independent verification): confirmed genuinely missing from production at bc28f653.
// Adaptation: ProcessRunnerTool (absent from production) -> SwiftCodeSubprocess.Subprocess.run; result.exitCode/stdout/stderr -> status/stdoutText/stderrText.
// Adaptation: AppError.gitError (SwiftCodeIDECore, not visible from SwiftCodeSDK) -> GitError.commandFailed (SourceControlKit's own error type; WorktreeManager precedent).
// Adaptation: GitCommit/GitBranch initialisers adapted to the destination models (shortHash/authorName/authorEmail; trackingRemote dropped, unused downstream).
// Adaptation: Depends on PreferencesStore (F2's slice, staged in staging-wire/unowned/) for the git_executable_path override.
import Foundation
import SwiftCodeSubprocess

public actor GitService {
    public static let shared = GitService()

    private var gitURL: URL {
        get async {
            if let customPath = await PreferencesStore.shared.get(forKey: "git_executable_path") as? String {
                return URL(fileURLWithPath: customPath)
            }

            // Try common paths to find a direct git executable that might not be a wrapper
            let commonPaths = [
                "/usr/local/bin/git",
                "/opt/homebrew/bin/git",
                "/Library/Developer/CommandLineTools/usr/bin/git",
                "/usr/bin/git"
            ]

            for path in commonPaths {
                if FileManager.default.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }

            return URL(fileURLWithPath: "/usr/bin/git")
        }
    }

    public func isGitInstalled() async -> Bool {
        let url = await gitURL
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    public func getStatus(for repositoryURL: URL) async throws -> GitStatusSnapshot {
        let result = try Subprocess.run(
            await gitURL.path,
            ["status", "--porcelain=v2", "--branch"],
            currentDirectory: repositoryURL
        )

        guard result.status == 0 else {
            throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText)
        }

        return GitPorcelainParser.shared.parseStatus(result.stdoutText, repositoryURL: repositoryURL)
    }

    public func stage(path: URL, repositoryURL: URL) async throws {
        let relPath = path.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
        let result = try Subprocess.run(
            await gitURL.path,
            ["add", relPath],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func unstage(path: URL, repositoryURL: URL) async throws {
        let relPath = path.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
        let result = try Subprocess.run(
            await gitURL.path,
            ["restore", "--staged", relPath],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func discardChanges(path: URL, repositoryURL: URL) async throws {
        let relPath = path.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
        _ = try? Subprocess.run(
            await gitURL.path,
            ["restore", relPath],
            currentDirectory: repositoryURL
        )
        _ = try? Subprocess.run(
            await gitURL.path,
            ["clean", "-f", relPath],
            currentDirectory: repositoryURL
        )
    }

    public func commit(message: String, repositoryURL: URL) async throws {
        let result = try Subprocess.run(
            await gitURL.path,
            ["commit", "-m", message],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func clone(remoteURL: URL, destinationURL: URL, token: String?) async throws {
        var env = ProcessInfo.processInfo.environment
        if let token = token {
            env["GIT_TERMINAL_PROMPT"] = "0"
        }

        let result = try Subprocess.run(
            await gitURL.path,
            ["clone", remoteURL.absoluteString, destinationURL.path],
            environment: env
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func getLog(repositoryURL: URL) async throws -> [GitCommit] {
        let result = try Subprocess.run(
            await gitURL.path,
            ["log", "--pretty=format:%H|%P|%an|%ae|%at|%s", "-n", "100"],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }

        return result.stdoutText.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count == 6 else { return nil }
            let parentHashes = parts[1].components(separatedBy: " ").filter { !$0.isEmpty }
            return GitCommit(
                hash: parts[0],
                shortHash: String(parts[0].prefix(7)),
                authorName: parts[2],
                authorEmail: parts[3],
                date: Date(timeIntervalSince1970: Double(parts[4]) ?? 0),
                message: parts[5],
                parentHashes: parentHashes
            )
        }
    }

    public func getBranches(repositoryURL: URL) async throws -> [GitBranch] {
        let result = try Subprocess.run(
            await gitURL.path,
            ["branch", "-a", "--format=%(refname:short)|%(HEAD)|%(upstream:short)"],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }

        return result.stdoutText.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count == 3 else { return nil }
            let name = parts[0]
            let isCurrent = parts[1] == "*"
            return GitBranch(name: name, isCurrent: isCurrent, isRemote: name.hasPrefix("origin/"))
        }
    }

    public func createBranch(name: String, repositoryURL: URL) async throws {
        let result = try Subprocess.run(
            await gitURL.path,
            ["checkout", "-b", name],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func checkout(branch: String, repositoryURL: URL) async throws {
        let result = try Subprocess.run(
            await gitURL.path,
            ["checkout", branch],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func deleteBranch(name: String, repositoryURL: URL) async throws {
        let result = try Subprocess.run(
            await gitURL.path,
            ["branch", "-d", name],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func getDiff(repositoryURL: URL) async throws -> [GitDiffHunk] {
        let result = try Subprocess.run(
            await gitURL.path,
            ["diff"],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
        return parseDiff(result.stdoutText)
    }

    public func rollback(to sha: String, repositoryURL: URL) async throws {
        let result = try Subprocess.run(
            await gitURL.path,
            ["reset", "--hard", sha],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func forcePush(branch: String, repositoryURL: URL) async throws {
        let result = try Subprocess.run(
            await gitURL.path,
            ["push", "origin", branch, "--force"],
            currentDirectory: repositoryURL
        )
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    public func push(repositoryURL: URL) async throws {
        // Run git push
        var result = try Subprocess.run(
            await gitURL.path,
            ["push"],
            currentDirectory: repositoryURL
        )
        if result.status != 0 {
            // Check if it's because of no upstream branch
            let stderr = result.stderrText.lowercased()
            if stderr.contains("no upstream") || stderr.contains("set-upstream") {
                // Get current branch
                let branchResult = try Subprocess.run(
                    await gitURL.path,
                    ["branch", "--show-current"],
                    currentDirectory: repositoryURL
                )
                let branch = branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if branchResult.exitCode == 0, !branch.isEmpty {
                    // Try pushing with -u origin branch
                    result = try Subprocess.run(
                        await gitURL.path,
                        ["push", "-u", "origin", branch],
                        currentDirectory: repositoryURL
                    )
                }
            }
        }
        if result.status != 0 { throw GitError.commandFailed(command: "git", exitCode: result.status, output: result.stderrText) }
    }

    private func parseDiff(_ output: String) -> [GitDiffHunk] {
        var hunks: [GitDiffHunk] = []
        let lines = output.components(separatedBy: .newlines)
        var currentHeader: String?
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("@@ ") {
                if let header = currentHeader {
                    hunks.append(GitDiffHunk(header: header, lines: currentLines))
                }
                currentHeader = line
                currentLines = []
            } else if currentHeader != nil {
                currentLines.append(line)
            }
        }
        if let header = currentHeader {
            hunks.append(GitDiffHunk(header: header, lines: currentLines))
        }
        return hunks
    }
}
