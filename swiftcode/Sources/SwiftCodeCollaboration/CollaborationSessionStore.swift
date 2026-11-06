// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Projects/Collaboration/CollaborationSessionStore.swift
// Adapted for SwiftCode: Legacy's Project replaced by CollaborationProject.

import Foundation

@MainActor
final class CollaborationSessionStore: ObservableObject {
    static let shared = CollaborationSessionStore()

    private var managers: [UUID: CollaborationManager] = [:]
    private init() {}

    func manager(for project: CollaborationProject, creatorID: String) -> CollaborationManager {
        if let existing = managers[project.id] {
            return existing
        }
        let manager = CollaborationManager(project: project, creatorID: creatorID)
        managers[project.id] = manager
        return manager
    }
}
