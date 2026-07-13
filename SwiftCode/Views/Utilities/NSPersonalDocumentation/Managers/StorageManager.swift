import Foundation
import SwiftData

@MainActor
public final class StorageManager: Sendable {
    public let container: ModelContainer
    public let context: ModelContext

    public init(projectURL: URL) throws {
        let storeURL = projectURL.appendingPathComponent(".swiftcode_personal_documentation.store")
        let config = ModelConfiguration(url: storeURL)

        let schema = Schema([
            Document.self,
            AttachmentRecord.self,
            Relationship.self,
            AIInsight.self,
            WikiPage.self,
            DocumentVersion.self,
            Template.self,
            SmartCollection.self,
            AnalyticsSnapshot.self
        ])

        self.container = try ModelContainer(for: schema, configurations: [config])
        self.context = ModelContext(container)
        self.context.autosaveEnabled = true
    }
}
