import Foundation

public struct GitServiceFileStatus: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case added
        case modified
        case deleted
        case renamed
        case untracked
        case conflicted
        case typeChanged
    }

    public var path: URL
    public var status: Kind

    public init(path: URL, status: Kind) {
        self.path = path
        self.status = status
    }
}

public struct GitServiceStatus: Sendable, Equatable {
    public var branch: String?
    public var files: [GitServiceFileStatus]

    public init(branch: String? = nil, files: [GitServiceFileStatus] = []) {
        self.branch = branch
        self.files = files
    }

    public var isClean: Bool { files.isEmpty }
}

public enum GitServiceError: LocalizedError, Sendable {
    case notInstalled(String)
    case commandFailed(command: String, status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let path): "git was not found at \(path)."
        case .commandFailed(let command, let status, let message):
            "git \(command) exited with status \(status): \(message)"
        }
    }
}

public actor GitService {
    public static let shared = GitService()

    private let gitPath: String

    public init(gitPath: String? = nil) {
        self.gitPath = gitPath ?? Self.locate()
    }

    public static func locate() -> String {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git", "/usr/bin/git"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/git"
    }

    public var executablePath: String { gitPath }

    public func isGitInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: gitPath)
    }

    public func getStatus(for repositoryURL: URL) async throws -> GitServiceStatus {
        let result = try run(["status", "--porcelain=v2", "--branch"], in: repositoryURL)
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "status", status: result.status, message: result.errorOutput)
        }
        return Self.parseStatus(result.output, repositoryURL: repositoryURL)
    }

    public func getDiff(repositoryURL: URL) async throws -> [GitDiffHunk] {
        let result = try run(["diff"], in: repositoryURL)
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "diff", status: result.status, message: result.errorOutput)
        }
        return Self.parseDiff(result.output)
    }

    public func getStagedDiff(repositoryURL: URL) async throws -> [GitDiffHunk] {
        let result = try run(["diff", "--cached"], in: repositoryURL)
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "diff --cached", status: result.status, message: result.errorOutput)
        }
        return Self.parseDiff(result.output)
    }

    public func stage(paths: [String], repositoryURL: URL) async throws {
        guard !paths.isEmpty else { return }
        let result = try run(["add", "--"] + paths, in: repositoryURL)
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "add", status: result.status, message: result.errorOutput)
        }
    }

    public func commit(message: String, repositoryURL: URL) async throws {
        let result = try run(["commit", "-m", message], in: repositoryURL)
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "commit", status: result.status, message: result.errorOutput)
        }
    }

    public func push(repositoryURL: URL) async throws {
        var result = try run(["push"], in: repositoryURL)
        if result.status != 0 {
            let lowered = result.errorOutput.lowercased()
            if lowered.contains("no upstream") || lowered.contains("set-upstream") {
                let branchResult = try run(["branch", "--show-current"], in: repositoryURL)
                let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if branchResult.status == 0, !branch.isEmpty {
                    result = try run(["push", "-u", "origin", branch], in: repositoryURL)
                }
            }
        }
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "push", status: result.status, message: result.errorOutput)
        }
    }

    public func currentBranch(repositoryURL: URL) async throws -> String {
        let result = try run(["branch", "--show-current"], in: repositoryURL)
        guard result.status == 0 else {
            throw GitServiceError.commandFailed(command: "branch --show-current", status: result.status, message: result.errorOutput)
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ arguments: [String], in directory: URL) throws -> (status: Int32, output: String, errorOutput: String) {
        guard FileManager.default.isExecutableFile(atPath: gitPath) else {
            throw GitServiceError.notInstalled(gitPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = environment

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        let errorData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus,
                String(decoding: outputData, as: UTF8.self),
                String(decoding: errorData, as: UTF8.self))
    }

    public static func parseStatus(_ output: String, repositoryURL: URL) -> GitServiceStatus {
        var branch: String?
        var files: [GitServiceFileStatus] = []

        for line in output.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("# branch.head ") {
                let name = String(line.dropFirst("# branch.head ".count))
                branch = name == "(detached)" ? nil : name
                continue
            }
            if line.hasPrefix("#") { continue }

            let fields = line.components(separatedBy: " ")
            guard let record = fields.first else { continue }

            switch record {
            case "1", "2":
                guard fields.count > 8 else { continue }
                let xy = fields[1]
                let path: String = record == "2" && fields.count > 10
                    ? fields[10...].joined(separator: " ")
                    : fields[8...].joined(separator: " ")
                files.append(GitServiceFileStatus(path: repositoryURL.appendingPathComponent(path),
                                                  status: kind(forXY: xy)))
            case "u":
                guard fields.count > 10 else { continue }
                let path = fields[10...].joined(separator: " ")
                files.append(GitServiceFileStatus(path: repositoryURL.appendingPathComponent(path), status: .conflicted))
            case "?":
                let path = String(line.dropFirst(2))
                files.append(GitServiceFileStatus(path: repositoryURL.appendingPathComponent(path), status: .untracked))
            default:
                continue
            }
        }

        return GitServiceStatus(branch: branch, files: files)
    }

    private static func kind(forXY xy: String) -> GitServiceFileStatus.Kind {
        let characters = Array(xy)
        let index = characters.count > 1 ? characters[1] : characters.first ?? " "
        switch index {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .added
        case "T": return .typeChanged
        default: return .modified
        }
    }

    public static func parseDiff(_ output: String) -> [GitDiffHunk] {
        var hunks: [GitDiffHunk] = []
        var header: String?
        var lines: [String] = []

        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("@@ ") {
                if let header { hunks.append(GitDiffHunk(header: header, lines: lines)) }
                header = line
                lines = []
            } else if header != nil {
                lines.append(line)
            }
        }
        if let header { hunks.append(GitDiffHunk(header: header, lines: lines)) }
        return hunks
    }
}
