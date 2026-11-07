import Foundation

public final class AgentSystemInitializer: Sendable {
    public static let shared = AgentSystemInitializer()

    private init() {}

    public func initialize() {
        Task {
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

            let baseDir = await SkillsRuntime.shared.getBaseSkillsDirectory()
            _ = try? await SkillsRuntime.shared.discoverSkills(in: baseDir)

            LoggingTool.info("Agent system initialized successfully.")

            if UserDefaults.standard.bool(forKey: "com.swiftcode.codex.completedSetup") {
                await CodexBridgeManager.shared.ensureBridgeRunning()
            }
        }
    }
}
