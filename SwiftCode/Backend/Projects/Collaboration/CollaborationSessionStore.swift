import UIKit
import Foundation

@MainActor
final class CollaborationSessionStore: ObservableObject {
    static let shared = CollaborationSessionStore()

    private var managers: [UUID: CollaborationManager] = [:]
    private init() {}

    func manager(for project: Project, creatorID: String) -> CollaborationManager {
        if let existing = managers[project.id] {
            return existing
        }
        let manager = CollaborationManager(project: project, creatorID: creatorID)
        managers[project.id] = manager
        return manager
    }
}
