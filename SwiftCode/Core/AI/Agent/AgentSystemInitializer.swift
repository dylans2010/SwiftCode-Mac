import Foundation

/// Responsible for early initialization of the Agentic AI systems at app launch.
public final class AgentSystemInitializer: Sendable {
    public static let shared = AgentSystemInitializer()

    private init() {}

    /// Performs necessary startup tasks for the agent system.
    public func initialize() {
        Task {
            // Discover skills from the current project root ONLY if it represents an actual project directory
            let currentPath = FileManager.default.currentDirectoryPath
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            if currentPath != "/" && currentPath != homePath {
                let projectRoot = URL(fileURLWithPath: currentPath)
                let fm = FileManager.default
                let isProject = fm.fileExists(atPath: projectRoot.appendingPathComponent(".git").path)
                    || fm.fileExists(atPath: projectRoot.appendingPathComponent("Package.swift").path)
                    || fm.fileExists(atPath: projectRoot.appendingPathComponent(".swiftcode").path)
                if isProject {
                    _ = try? await SkillsRuntime.shared.discoverSkills(in: projectRoot)
                }
            }

            // Also discover global skills from Application Support
            let baseDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
            _ = try? await SkillsRuntime.shared.discoverSkills(in: baseDir)

            LoggingTool.info("Agent system initialized successfully.")

            // Automatically launch the bridge if Codex setup was completed previously
            if UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup") {
                await CodexBridgeManager.shared.ensureBridgeRunning()
            }
        }
    }
}
