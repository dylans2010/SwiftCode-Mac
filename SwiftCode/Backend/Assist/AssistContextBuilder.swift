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

    public func buildContext(sessionId: UUID) -> AssistContext {
        let project = ProjectSessionStore.shared.activeProject
        let workspaceRoot = project?.directoryURL ?? URL(fileURLWithPath: "/")

        return AssistContext(
            sessionId: sessionId,
            project: project,
            workspaceRoot: workspaceRoot,
            memory: memory,
            logger: logger,
            fileSystem: fileSystem,
            git: git,
            permissions: permissions,
            safetyLevel: .balanced, // Default
            isAutonomous: true
        )
    }
}
