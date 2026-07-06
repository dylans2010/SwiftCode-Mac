import SwiftUI
import Observation

@Observable
@MainActor
public class HomeViewModel {
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
        let entry = ProjectRegistryEntry(
            name: url.lastPathComponent,
            rootURL: url,
            kind: url.pathExtension == "xcodeproj" ? .xcodeProject : .folder
        )
        if !recentProjects.contains(where: { $0.rootURL == url }) {
            recentProjects.insert(entry, at: 0)
            try? await ProjectRegistryStore.shared.save(recentProjects)
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
