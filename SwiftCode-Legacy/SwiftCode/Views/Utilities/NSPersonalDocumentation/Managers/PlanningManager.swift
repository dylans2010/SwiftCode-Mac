import Foundation
import Observation

@Observable
@MainActor
public final class PlanningManager {
    private let documentManager: DocumentManager

    public init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }

    public func fetchPlanningItems(for kind: ModuleKind) throws -> [Document] {
        try documentManager.fetchDocuments(for: kind)
    }

    public func createPlanningItem(title: String, kind: ModuleKind, status: String, priority: String) throws -> Document {
        let doc = try documentManager.createDocument(title: title, kind: kind)
        doc.status = status
        doc.priority = priority
        try documentManager.updateDocument(doc)
        return doc
    }
}
