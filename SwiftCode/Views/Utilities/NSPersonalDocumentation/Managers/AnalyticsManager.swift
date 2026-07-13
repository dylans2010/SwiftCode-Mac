import Foundation
import SwiftData

@MainActor
public final class AnalyticsManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func logEvent(_ name: String, metadata: [String: String]? = nil) throws {
        var metaStr: String? = nil
        if let metadata = metadata, let data = try? JSONEncoder().encode(metadata) {
            metaStr = String(data: data, encoding: .utf8)
        }

        let snapshot = AnalyticsSnapshot(projectID: projectID, eventName: name, metadataString: metaStr)
        storage.context.insert(snapshot)
        try storage.context.save()
    }

    public func fetchEventCount(named name: String) throws -> Int {
        let descriptor = FetchDescriptor<AnalyticsSnapshot>()
        let all = try storage.context.fetch(descriptor)
        return all.filter { $0.projectID == projectID && $0.eventName == name }.count
    }
}
