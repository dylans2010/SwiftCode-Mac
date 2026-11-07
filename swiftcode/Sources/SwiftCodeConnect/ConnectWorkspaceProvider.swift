import Foundation

public struct ConnectProjectSummary: Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var path: String
    public var scheme: String
    public var destinations: [String]
    public var swiftVersion: String

    public init(id: UUID = UUID(), name: String, path: String, scheme: String,
                destinations: [String] = ["macOS"], swiftVersion: String = "6.0") {
        self.id = id
        self.name = name
        self.path = path
        self.scheme = scheme
        self.destinations = destinations
        self.swiftVersion = swiftVersion
    }

    public var directoryURL: URL { URL(fileURLWithPath: path) }

    public var connectProjectInfo: ConnectProjectInfo {
        ConnectProjectInfo(id: id.uuidString, name: name, path: path,
                           activeScheme: scheme, activeTarget: name,
                           destinations: destinations, swiftVersion: swiftVersion)
    }
}

public struct ConnectGitStatus: Sendable {
    public var branch: String
    public var isClean: Bool
    public var ahead: Int
    public var behind: Int
    public var modifiedFiles: [String]
    public var stagedFiles: [String]
    public var untrackedFiles: [String]

    public init(branch: String, isClean: Bool, ahead: Int = 0, behind: Int = 0,
                modifiedFiles: [String] = [], stagedFiles: [String] = [],
                untrackedFiles: [String] = []) {
        self.branch = branch
        self.isClean = isClean
        self.ahead = ahead
        self.behind = behind
        self.modifiedFiles = modifiedFiles
        self.stagedFiles = stagedFiles
        self.untrackedFiles = untrackedFiles
    }
}

public struct ConnectBuildOutcome: Sendable {
    public var success: Bool
    public var diagnostics: [ConnectBuildDiagnosticPayload]
    public var errorCount: Int
    public var warningCount: Int

    public init(success: Bool, diagnostics: [ConnectBuildDiagnosticPayload] = [],
                errorCount: Int = 0, warningCount: Int = 0) {
        self.success = success
        self.diagnostics = diagnostics
        self.errorCount = errorCount
        self.warningCount = warningCount
    }
}

public struct ConnectTestOutcome: Sendable {
    public var success: Bool
    public var message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

public protocol ConnectWorkspaceProvider: Sendable {
    var activeProject: ConnectProjectSummary? { get }
    var availableProjects: [ConnectProjectSummary] { get }
    func gitStatus(at root: URL) async throws -> ConnectGitStatus
    func gitBranches(at root: URL) async throws -> [String]
    func buildProject(scheme: String?, at root: URL) async throws -> ConnectBuildOutcome
    func runTests(scheme: String?, at root: URL) async throws -> ConnectTestOutcome
    func assist(query: String, contextFiles: [String]?, projectName: String) async throws -> String
    func devices() async -> [ConnectDeviceItem]
}

public struct ConnectUnavailableWorkspaceProvider: ConnectWorkspaceProvider {
    public static let shared = ConnectUnavailableWorkspaceProvider()
    public init() {}

    public var activeProject: ConnectProjectSummary? { nil }
    public var availableProjects: [ConnectProjectSummary] { [] }

    public func gitStatus(at root: URL) async throws -> ConnectGitStatus {
        throw ConnectErrorPayload(code: ConnectErrorCode.deviceUnavailable.rawValue,
                                  message: "No workspace is configured on this Mac.")
    }
    public func gitBranches(at root: URL) async throws -> [String] {
        throw ConnectErrorPayload(code: ConnectErrorCode.deviceUnavailable.rawValue,
                                  message: "No workspace is configured on this Mac.")
    }
    public func buildProject(scheme: String?, at root: URL) async throws -> ConnectBuildOutcome {
        throw ConnectErrorPayload(code: ConnectErrorCode.deviceUnavailable.rawValue,
                                  message: "No workspace is configured on this Mac.")
    }
    public func runTests(scheme: String?, at root: URL) async throws -> ConnectTestOutcome {
        throw ConnectErrorPayload(code: ConnectErrorCode.deviceUnavailable.rawValue,
                                  message: "No workspace is configured on this Mac.")
    }
    public func assist(query: String, contextFiles: [String]?, projectName: String) async throws -> String {
        throw ConnectErrorPayload(code: ConnectErrorCode.notSupported.rawValue,
                                  message: "Assist is not configured on this Mac.")
    }
    public func devices() async -> [ConnectDeviceItem] { [] }
}

public enum ConnectLocalGit {
    @discardableResult
    private static func runGit(_ args: [String], at root: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ConnectErrorPayload(code: ConnectErrorCode.internalError.rawValue,
                                      message: "git \(args.first ?? "") failed with exit code \(process.terminationStatus).")
        }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    public static func status(at root: URL) throws -> ConnectGitStatus {
        let output = try runGit(["status", "--porcelain=v1", "--branch"], at: root)
        var branch = ""
        var ahead = 0
        var behind = 0
        var modified: [String] = []
        var staged: [String] = []
        var untracked: [String] = []
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                let header = String(line.dropFirst(3))
                branch = header.components(separatedBy: "...").first ?? header
                if let range = header.range(of: "ahead ") {
                    ahead = Int(header[range.upperBound...].components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") ?? 0
                }
                if let range = header.range(of: "behind ") {
                    behind = Int(header[range.upperBound...].components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? "") ?? 0
                }
                continue
            }
            guard line.count >= 4 else { continue }
            let path = String(line.dropFirst(3))
            let indexStatus = line[line.startIndex]
            let worktreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
            if indexStatus == "?" || worktreeStatus == "?" {
                untracked.append(path)
            } else {
                if indexStatus != " " && indexStatus != "." { staged.append(path) }
                if worktreeStatus == "M" || worktreeStatus == "D" || worktreeStatus == "T" { modified.append(path) }
            }
        }
        let isClean = modified.isEmpty && staged.isEmpty && untracked.isEmpty
        return ConnectGitStatus(branch: branch, isClean: isClean, ahead: ahead, behind: behind,
                                modifiedFiles: modified, stagedFiles: staged, untrackedFiles: untracked)
    }

    public static func branches(at root: URL) throws -> [String] {
        let output = try runGit(["branch", "--format=%(refname:short)"], at: root)
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
