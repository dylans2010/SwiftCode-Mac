import Foundation
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
        recentProjects.append(entry)
        try? await ProjectRegistryStore.shared.save(recentProjects)
    }
}
