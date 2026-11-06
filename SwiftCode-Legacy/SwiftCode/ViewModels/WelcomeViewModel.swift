import SwiftUI
import Observation

@Observable
@MainActor
public class WelcomeViewModel {
    public var recentProjects: [ProjectRegistryEntry] = []
    public var isCloning = false

    public init() {}

    public func loadProjects() async {
        do {
            recentProjects = try await ProjectRegistryStore.shared.load()
        } catch {
            LoggingTool.error("Failed to load project registry: \(error)")
        }
    }

    public func importProject(url: URL) async {
        do {
            _ = try ProjectSessionStore.shared.createProject(name: url.lastPathComponent)
        } catch {
            LoggingTool.error("Failed to import project: \(error)")
        }
    }

    public func createProject(at url: URL) async {
        await importProject(url: url)
    }

    public func removeProject(_ project: ProjectRegistryEntry) async {
        recentProjects.removeAll { $0.id == project.id }
        do {
            try await ProjectRegistryStore.shared.save(recentProjects)
        } catch {
            LoggingTool.error("Failed to save project registry after deletion: \(error)")
        }
    }
}
