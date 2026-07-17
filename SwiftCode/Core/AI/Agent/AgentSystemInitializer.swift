import Foundation

/// Responsible for early initialization of the Agentic AI systems at app launch.
public final class AgentSystemInitializer: Sendable {
    public static let shared = AgentSystemInitializer()

    private init() {}

    /// Performs necessary startup tasks for the agent system.
    public func initialize() {
        Task {
            // Discover skills from the current project root if available
            let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            do {
                _ = try await SkillsRuntime.shared.discoverSkills(in: projectRoot)

                // Also discover global skills from Application Support
                let baseDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
                _ = try await SkillsRuntime.shared.discoverSkills(in: baseDir)

                LoggingTool.info("Agent system initialized successfully.")

                // Automatically launch the bridge if Codex setup was completed previously
                if UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup") {
                    await CodexBridgeManager.shared.ensureBridgeRunning()
                }
            } catch {
                LoggingTool.error("Failed to initialize Agent System: \(error)")
            }
        }
    }
}
