import Foundation

public actor IndexingManager {
    private var invertedIndex: [String: Set<UUID>] = [:]

    public init() {}

    public func indexDocument(id: UUID, content: String) {
        let words = content.components(separatedBy: .alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.count > 2 }

        for word in words {
            if invertedIndex[word] == nil {
                invertedIndex[word] = []
            }
            invertedIndex[word]?.insert(id)
        }
    }

    public func removeDocument(id: UUID) {
        for (word, ids) in invertedIndex {
            if ids.contains(id) {
                var updated = ids
                updated.remove(id)
                if updated.isEmpty {
                    invertedIndex.removeValue(forKey: word)
                } else {
                    invertedIndex[word] = updated
                }
            }
        }
    }

    public func searchInIndex(word: String) -> Set<UUID> {
        invertedIndex[word.lowercased()] ?? []
    }
}
