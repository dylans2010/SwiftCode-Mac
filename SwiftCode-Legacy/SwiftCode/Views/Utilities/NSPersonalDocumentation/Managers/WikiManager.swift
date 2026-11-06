import Foundation
import Observation
import SwiftData

@Observable
@MainActor
public final class WikiManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchWikiPages() throws -> [WikiPage] {
        let descriptor = FetchDescriptor<WikiPage>()
        let all = try storage.context.fetch(descriptor)
        return all.filter { $0.projectID == projectID }
    }

    public func createOrUpdateWikiPage(title: String, content: String) throws -> WikiPage {
        let existing = try fetchWikiPages()
        if let page = existing.first(where: { $0.title == title }) {
            page.markdownSource = content
            page.lastUpdated = Date()
            page.isStale = false
            try storage.context.save()
            return page
        } else {
            let page = WikiPage(projectID: projectID, title: title, markdownSource: content)
            storage.context.insert(page)
            try storage.context.save()
            return page
        }
    }
}
