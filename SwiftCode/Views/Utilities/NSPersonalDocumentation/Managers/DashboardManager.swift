import Foundation
import Observation

@Observable
@MainActor
public final class DashboardManager {
    private let documentManager: DocumentManager

    public init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }

    // Safe because DashboardSnapshot is initialized and used entirely on the @MainActor-isolated thread/context.
    public struct DashboardSnapshot: @unchecked Sendable {
        public let totalDocuments: Int
        public let totalTasks: Int
        public let completedTasks: Int
        public let recentDocuments: [Document]
    }

    public func getSnapshot() async throws -> DashboardSnapshot {
        let docs = try documentManager.fetchDocuments()
        let recent = Array(docs.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
        return DashboardSnapshot(
            totalDocuments: docs.count,
            totalTasks: docs.filter { $0.archetype == "structured" }.count,
            completedTasks: docs.filter { $0.status == "Done" }.count,
            recentDocuments: recent
        )
    }
}
