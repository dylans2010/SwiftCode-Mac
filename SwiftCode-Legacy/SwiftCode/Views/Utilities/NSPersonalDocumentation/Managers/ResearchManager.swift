import Foundation
import Observation

@Observable
@MainActor
public final class ResearchManager {
    private let documentManager: DocumentManager

    public init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }

    public func fetchResearchItems() throws -> [Document] {
        try documentManager.fetchDocuments(for: .researchLibrary)
    }

    public func addReference(title: String, urlString: String) throws -> Document {
        try documentManager.createDocument(title: title, kind: .referenceLibrary, markdown: "URL: \(urlString)")
    }
}
