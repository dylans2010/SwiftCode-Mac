// The host seam for SwiftCode Connect.
//
// Legacy's Connect services reached straight into app singletons
// (`ProjectSessionStore.shared.activeProject`, `GitService`,
// `XcodeBuildAPI`, `DeviceManager`, the Assist tool internals). Ycode has
// no such singletons, and Connect must not acquire them: the IDE shell
// supplies a workspace provider, and Connect only ever talks to that
// protocol. Until the shell wires one in, every service answers honestly
// with NO_ACTIVE_PROJECT / a named error instead of inventing a project.
//
// Wiring (for the coordinator/parent — not done here, this file only
// defines the seam): the macOS shell sets
// `ConnectServer.shared.workspaceProvider` from the open workspace
// (`WorkspaceSession`), with git via `/usr/bin/git` (see `ConnectLocalGit`
// below), builds/tests via `YcodeBuild`/`YcodeXcodebuild`, assist via
// `CodingAssistantModel`, and devices via the Device Hub / `simctl`.

import Foundation

/// A project as SwiftCode Connect reports it: identity, name, on-disk path,
/// and the build metadata the sync payload carries.
public struct ConnectProjectSummary: Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    /// On-disk path of the project root.
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

    /// The wire form the sync/project responses carry.
    public var connectProjectInfo: ConnectProjectInfo {
        ConnectProjectInfo(id: id.uuidString, name: name, path: path,
                           activeScheme: scheme, activeTarget: name,
                           destinations: destinations, swiftVersion: swiftVersion)
    }
}

/// The git status of a project root, in the shape the git-status response
/// carries. Produced by the provider (see `ConnectLocalGit` for a
/// `/usr/bin/git` implementation the shell can reuse).
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

/// The outcome of a remote-triggered build, in the shape the build-completed
/// broadcast carries.
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

/// The outcome of a remote-triggered test run.
public struct ConnectTestOutcome: Sendable {
    public var success: Bool
    public var message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

/// What the Mac-side IDE offers a connected iOS device. Every method is
/// host-supplied: Connect itself knows no project, no git binary, no build
/// engine, and no assistant. A method throws when its capability is not
/// configured, and the calling service turns that into a wire error instead
/// of a canned success.
public protocol ConnectWorkspaceProvider: Sendable {
    /// The project the IDE currently has open, if any.
    var activeProject: ConnectProjectSummary? { get }
    /// Every project the IDE knows about (the library), for the project list.
    var availableProjects: [ConnectProjectSummary] { get }
    /// `git status` for a project root (see `ConnectLocalGit.status`).
    func gitStatus(at root: URL) async throws -> ConnectGitStatus
    /// Local branch names for a project root (see `ConnectLocalGit.branches`).
    func gitBranches(at root: URL) async throws -> [String]
    /// Build the project at `root` for `scheme` (nil: the project's default).
    func buildProject(scheme: String?, at root: URL) async throws -> ConnectBuildOutcome
    /// Run the tests of the project at `root` for `scheme`.
    func runTests(scheme: String?, at root: URL) async throws -> ConnectTestOutcome
    /// Answer an assist query in the context of the named project. This is
    /// the only route an assist answer may take: Legacy answered with a
    /// canned string ("Prompt received: ..."), which this port refuses to
    /// reproduce — no handler means an honest error, never a fake answer.
    func assist(query: String, contextFiles: [String]?, projectName: String) async throws -> String
    /// Devices the IDE can run on (simulators / connected devices).
    func devices() async -> [ConnectDeviceItem]
}

/// The provider used until the shell wires a real one: no project, and
/// every operation fails with a named error. Connect stays silent about
/// nothing — the device gets NO_ACTIVE_PROJECT / NOT_CONFIGURED, never an
/// empty success.
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

/// `/usr/bin/git` implementations of the provider's git methods, for the
/// shell's provider to reuse. No dependency on any git library: `status`
/// parses `git status --porcelain=v1 --branch`, `branches` parses
/// `git branch --format=%(refname:short)`.
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
