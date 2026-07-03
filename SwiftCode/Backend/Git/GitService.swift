import Foundation

public actor GitService {
    public static let shared = GitService()

    private let gitURL = URL(fileURLWithPath: "/usr/bin/git")

    public func getStatus(for repositoryURL: URL) async throws -> GitStatusSnapshot {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["status", "--porcelain=v2", "--branch"],
            workingDirectory: repositoryURL
        )

        guard result.exitCode == 0 else {
            throw AppError.gitError(result.stderr)
        }

        return GitPorcelainParser.shared.parseStatus(result.stdout, repositoryURL: repositoryURL)
    }

    public func stage(path: URL, repositoryURL: URL) async throws {
        let relPath = path.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["add", relPath],
            workingDirectory: repositoryURL
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func unstage(path: URL, repositoryURL: URL) async throws {
        let relPath = path.path.replacingOccurrences(of: repositoryURL.path + "/", with: "")
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["restore", "--staged", relPath],
            workingDirectory: repositoryURL
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func commit(message: String, repositoryURL: URL) async throws {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["commit", "-m", message],
            workingDirectory: repositoryURL
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func clone(remoteURL: URL, destinationURL: URL, token: String?) async throws {
        var env = ProcessInfo.processInfo.environment
        if let token = token {
            env["GIT_TERMINAL_PROMPT"] = "0"
        }

        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["clone", remoteURL.absoluteString, destinationURL.path],
            environment: env
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }
    }

    public func getLog(repositoryURL: URL) async throws -> [GitCommit] {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["log", "--pretty=format:%H|%an|%ae|%at|%s", "-n", "100"],
            workingDirectory: repositoryURL
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }

        return result.stdout.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count == 5 else { return nil }
            return GitCommit(
                hash: parts[0],
                author: parts[1],
                email: parts[2],
                date: Date(timeIntervalSince1970: Double(parts[3]) ?? 0),
                message: parts[4],
                parentHashes: []
            )
        }
    }

    public func getBranches(repositoryURL: URL) async throws -> [GitBranch] {
        let result = try await ProcessRunnerTool.shared.run(
            executableURL: gitURL,
            arguments: ["branch", "-a", "--format=%(refname:short)|%(HEAD)"],
            workingDirectory: repositoryURL
        )
        if result.exitCode != 0 { throw AppError.gitError(result.stderr) }

        return result.stdout.components(separatedBy: .newlines).compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count == 2 else { return nil }
            let name = parts[0]
            let isCurrent = parts[1] == "*"
            return GitBranch(name: name, isCurrent: isCurrent, isRemote: name.hasPrefix("origin/"))
        }
    }
}
