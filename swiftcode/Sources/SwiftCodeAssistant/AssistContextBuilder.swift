// Ported from Legacy `SwiftCode/Backend/Assist/AssistContextBuilder.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim. BLOCKED references (left intact, owned by other scopes):
// - ProjectSessionStore (Legacy `SwiftCode/Services/ProjectSessionStore.swift`, PARTIAL):
//   RESOLVED by fix W-V2 — the builder no longer reads the store (SwiftCodeIDECore,
//   unreachable from this target). It takes the project as `AssistProject` (see
//   AssistProject.swift); the IDE shell sets it when a project opens, and until
//   then the workspace root on disk is the project.
// - AssistWorkingDirectoryStore / AssistFileSystem: audit COVERED-by-design — the
//   destination superseded them with the MCP tools (WorkspaceSession.currentDirectory
//   + dir_cd/dir_pwd in SwiftCodeMCP). The working-directory restore in buildContext
//   (`as? AssistFileSystem` + AssistWorkingDirectoryStore) must be re-wired by the
//   coordinator to WorkspaceSession.currentDirectory; it is kept verbatim here so
//   the behaviour is not silently dropped.
// Resolved in-destination: AssistContext + AssistContextEngine + ExecutionMode +
// the component protocols all exist in SwiftCodeAssistant.
// Wiring: AssistManager.buildContext() (same batch) and any session bootstrap.

import Foundation

@MainActor
public final class AssistContextBuilder {
    private let logger: AssistLoggerProtocol
    private let permissions: AssistPermissionsManagerProtocol
    private let memory: AssistMemoryGraphProtocol
    private let fileSystem: AssistFileSystemProtocol
    private let git: AssistGitManagerProtocol

    /// The project this builder builds contexts for. Set by the host (the
    /// IDE shell passes the active project here); nil until then, in which
    /// case the workspace root on disk is the project (see buildContext).
    public var activeProject: AssistProject?

    public init(
        logger: AssistLoggerProtocol,
        permissions: AssistPermissionsManagerProtocol,
        memory: AssistMemoryGraphProtocol,
        fileSystem: AssistFileSystemProtocol,
        git: AssistGitManagerProtocol,
        project: AssistProject? = nil
    ) {
        self.logger = logger
        self.permissions = permissions
        self.memory = memory
        self.fileSystem = fileSystem
        self.git = git
        self.activeProject = project
    }

    public static func resolvedWorkspaceRoot(project: AssistProject? = nil) -> URL {
        if let projectURL = project?.directoryURL {
            return projectURL
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let fallback = documents.appendingPathComponent("SwiftCodeProjects/DefaultProject", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public func buildContext(sessionId: UUID) -> AssistContext {
        let workspaceRoot = activeProject?.directoryURL ?? AssistContextBuilder.resolvedWorkspaceRoot()
        let project = activeProject ?? AssistProject(workspaceRoot: workspaceRoot)

        // Re-apply the session's stored working directory (see dir_cd) so a
        // cd survives context rebuilds across messages in the same session.
        if let fs = fileSystem as? AssistFileSystem {
            let stored = AssistWorkingDirectoryStore.shared.currentDirectory(for: sessionId, workspaceRoot: workspaceRoot)
            if stored.path != workspaceRoot.path {
                try? fs.restoreCurrentDirectory(stored)
            }
        }

        let executionModeRaw = UserDefaults.standard.string(forKey: "com.swiftcode.assist.executionMode") ?? ExecutionMode.autopilot.rawValue
        let executionMode = ExecutionMode(rawValue: executionModeRaw) ?? .autopilot

        return AssistContext(
            sessionId: sessionId,
            project: project,
            workspaceRoot: workspaceRoot,
            memory: memory,
            logger: logger,
            fileSystem: fileSystem,
            git: git,
            permissions: permissions,
            safetyLevel: .balanced,
            isAutonomous: true,
            sessionExecutionMode: executionMode
        )
    }

    public func buildContextEngine(sessionId: UUID) -> AssistContextEngine {
        let context = buildContext(sessionId: sessionId)
        return AssistContextEngine(context: context)
    }
}
