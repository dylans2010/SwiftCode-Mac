import Foundation
import Observation

@Observable
@MainActor
public final class JournalManager {
    private let documentManager: DocumentManager

    public init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }

    public func getOrCreateDailyNote(for date: Date = Date()) throws -> Document {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let title = "Daily Note — \(formatter.string(from: date))"
        let existing = try documentManager.fetchDocuments(for: .dailyNotes)
        if let found = existing.first(where: { $0.title == title }) {
            return found
        }
        return try documentManager.createDocument(title: title, kind: .dailyNotes, markdown: "# \(title)\n\n## Today's Focus\n- \n\n## Tasks\n- [ ] ")
    }
}
