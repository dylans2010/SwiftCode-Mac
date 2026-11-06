import Foundation
import DiagnosticsKit
import WorkspaceKit

public enum GitError: Error, LocalizedError, Sendable {
    case notARepository(String)
    case commandFailed(command: String, exitCode: Int32, output: String)
    case invalidBranch(String)

    public var errorDescription: String? {
        switch self {
        case .notARepository(let path):
            return "Path is not inside a Git repository: \(path)"
        case .commandFailed(let cmd, let code, let out):
            return "Git command '\(cmd)' failed with exit code \(code): \(out)"
        case .invalidBranch(let branch):
            return "Invalid Git branch: \(branch)"
        }
    }
}

public final class SourceControlService: Sendable {
    private let gitPath: String

    public init(gitPath: String = "/usr/bin/git") {
        self.gitPath = gitPath
    }

    private func runGit(args: [String], in directory: String) throws -> String {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitError.commandFailed(command: args.joined(separator: " "), exitCode: -1, output: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(
                command: args.joined(separator: " "),
                exitCode: process.terminationStatus,
                output: stderr.isEmpty ? stdout : stderr
            )
        }
        return stdout
    }

    public func isGitRepository(at path: String) -> Bool {
        do {
            let out = try runGit(args: ["rev-parse", "--is-inside-work-tree"], in: path)
            return out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    public func getStatus(at path: String) throws -> GitStatus {
        guard isGitRepository(at: path) else {
            throw GitError.notARepository(path)
        }

        let raw = try runGit(args: ["status", "--porcelain=v1", "-b"], in: path)
        let lines = raw.components(separatedBy: .newlines)

        var currentBranch = "main"
        var upstream: String? = nil
        var ahead = 0
        var behind = 0
        var files: [GitFileStatus] = []

        for line in lines {
            if line.hasPrefix("## ") {
                let header = String(line.dropFirst(3))
                // parse branch info: e.g. "main...origin/main [ahead 1, behind 2]"
                let parts = header.components(separatedBy: "...")
                currentBranch = parts.first?.trimmingCharacters(in: .whitespaces) ?? "HEAD"
                if parts.count > 1 {
                    let rest = parts[1]
                    if let openBracket = rest.firstIndex(of: "[") {
                        upstream = String(rest[..<openBracket]).trimmingCharacters(in: .whitespaces)
                        let bracketContent = rest[openBracket...].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                        if bracketContent.contains("ahead") {
                            ahead = 1
                        }
                        if bracketContent.contains("behind") {
                            behind = 1
                        }
                    } else {
                        upstream = rest.trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if line.count >= 3 {
                let indexStatus = line[line.startIndex]
                let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
                let filePath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)

                if indexStatus == "?" && workTreeStatus == "?" {
                    files.append(GitFileStatus(path: filePath, status: .untracked, isStaged: false))
                } else {
                    if indexStatus != " " && indexStatus != "?" {
                        files.append(GitFileStatus(path: filePath, status: .modified, isStaged: true))
                    }
                    if workTreeStatus != " " && workTreeStatus != "?" {
                        files.append(GitFileStatus(path: filePath, status: .modified, isStaged: false))
                    }
                }
            }
        }

        return GitStatus(
            isClean: files.isEmpty,
            currentBranch: currentBranch,
            upstreamBranch: upstream,
            aheadCount: ahead,
            behindCount: behind,
            files: files
        )
    }

    public func getDiff(at path: String, staged: Bool = false) throws -> String {
        guard isGitRepository(at: path) else {
            throw GitError.notARepository(path)
        }
        var args = ["diff"]
        if staged {
            args.append("--cached")
        }
        return try runGit(args: args, in: path)
    }

    public func getLog(at path: String, limit: Int = 10) throws -> [GitCommit] {
        guard isGitRepository(at: path) else {
            throw GitError.notARepository(path)
        }
        let format = "%H|%h|%an|%ae|%at|%s"
        let raw = try runGit(args: ["log", "-n", "\(limit)", "--pretty=format:\(format)"], in: path)
        var commits: [GitCommit] = []

        for line in raw.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 6 else { continue }
            let hash = parts[0]
            let shortHash = parts[1]
            let name = parts[2]
            let email = parts[3]
            let timestamp = Double(parts[4]) ?? 0
            let message = parts[5]

            commits.append(GitCommit(
                hash: hash,
                shortHash: shortHash,
                authorName: name,
                authorEmail: email,
                date: Date(timeIntervalSince1970: timestamp),
                message: message
            ))
        }
        return commits
    }
}
