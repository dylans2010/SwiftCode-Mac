// STAGED PORT — SwiftCode-Legacy `SwiftCode/Core/AI/Agent/AgentSystemInitializer.swift`
// (Legacy main d51a8f0d; Dylan's own code, direct port authorised under MIT).
// Target: SwiftCodeAssistant.
//
// ADAPTATIONS (destination equivalents used instead of Legacy-only types):
//   - SkillsRuntime: EXISTS in SwiftCodeAssistant (same discoverSkills(in:)
//     API); its getBaseSkillsDirectory() is synchronous in the destination,
//     so the `await` on that call is dropped. Behaviour unchanged.
//   - LoggingTool (lives in SwiftCodeIDECore — NOT a SwiftCodeAssistant
//     dependency, so it cannot be imported here) -> os.Logger, following the
//     same replacement already used by SkillsRuntime.swift in this target.
//   - CodexBridgeManager.shared.ensureBridgeRunning(): resolves against the
//     CodexBridgeManager staged alongside this file in this same batch.
// No missing dependencies remain for this file.

import Foundation
import os

private let agentSystemInitializerLogger = Logger(subsystem: "com.swiftcode.AgentSystem", category: "AgentSystemInitializer")

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
            let baseDir = SkillsRuntime.shared.getBaseSkillsDirectory()
            _ = try? await SkillsRuntime.shared.discoverSkills(in: baseDir)

            agentSystemInitializerLogger.info("Agent system initialized successfully.")

            // Automatically launch the bridge if Codex setup was completed previously
            if UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup") {
                await CodexBridgeManager.shared.ensureBridgeRunning()
            }
        }
    }
}
