import Foundation
import SwiftData

@MainActor
public final class TemplateManager {
    private let storage: StorageManager
    private let projectID: UUID

    public init(storage: StorageManager, projectID: UUID) {
        self.storage = storage
        self.projectID = projectID
    }

    public func fetchTemplates(for kind: ModuleKind) throws -> [Template] {
        let descriptor = FetchDescriptor<Template>()
        let all = try storage.context.fetch(descriptor)
        let filtered = all.filter { $0.projectID == nil || $0.projectID == projectID }
        return filtered.filter { $0.moduleKind == kind }
    }

    public func createTemplate(title: String, description: String, markdown: String, for kind: ModuleKind, isGlobal: Bool = false) throws -> Template {
        let template = Template(
            projectID: isGlobal ? nil : projectID,
            moduleKind: kind,
            title: title,
            descriptionText: description,
            markdownSource: markdown
        )
        storage.context.insert(template)
        try storage.context.save()
        return template
    }

    public func seedDefaultTemplates() throws {
        let existing = try storage.context.fetch(FetchDescriptor<Template>())
        if existing.isEmpty {
            _ = try createTemplate(title: "Standard Meeting Notes", description: "Template for routine dev syncs", markdown: "## Attendees\n- \n\n## Discussion\n- ", for: .meetingNotes, isGlobal: true)
            _ = try createTemplate(title: "Bug Report Schema", description: "Standard QA layout", markdown: "## Repro Steps\n1. \n\n## Expected\n\n## Actual\n", for: .bugDatabase, isGlobal: true)
        }
    }
}
