import Foundation

@MainActor
public final class AssistContextBuilder {
    private let logger: AssistLoggerProtocol
    private let permissions: AssistPermissionsManagerProtocol
    private let memory: AssistMemoryGraphProtocol
    private let fileSystem: AssistFileSystemProtocol
    private let git: AssistGitManagerProtocol

    public init(
        logger: AssistLoggerProtocol,
        permissions: AssistPermissionsManagerProtocol,
        memory: AssistMemoryGraphProtocol,
        fileSystem: AssistFileSystemProtocol,
        git: AssistGitManagerProtocol
    ) {
        self.logger = logger
        self.permissions = permissions
        self.memory = memory
        self.fileSystem = fileSystem
        self.git = git
    }

    public static func resolvedWorkspaceRoot() -> URL {
        if let projectURL = ProjectSessionStore.shared.activeProject?.directoryURL {
            return projectURL
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let fallback = documents.appendingPathComponent("SwiftCodeProjects/DefaultProject", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public func buildContext(sessionId: UUID) -> AssistContext {
        let project = ProjectSessionStore.shared.activeProject
        let workspaceRoot = project?.directoryURL ?? AssistContextBuilder.resolvedWorkspaceRoot()

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
