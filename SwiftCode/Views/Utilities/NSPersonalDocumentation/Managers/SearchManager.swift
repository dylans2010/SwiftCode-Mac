import Foundation

@MainActor
public final class SearchManager {
    private let documentManager: DocumentManager
    private let indexingManager: IndexingManager

    public init(documentManager: DocumentManager, indexingManager: IndexingManager) {
        self.documentManager = documentManager
        self.indexingManager = indexingManager
    }

    public struct SearchResult: Sendable, Identifiable {
        public var id: UUID { document.id }
        public let document: Document
        public let score: Int
        public let snippet: String
    }

    public func search(query: String) throws -> [SearchResult] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return [] }

        let docs = try documentManager.fetchDocuments()

        for doc in docs {
            Task {
                await indexingManager.indexDocument(id: doc.id, content: doc.title + " " + doc.markdownSource)
            }
        }

        var results: [SearchResult] = []
        let queryWords = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        for doc in docs {
            var score = 0
            var snippet = ""

            let titleLower = doc.title.lowercased()
            let contentLower = doc.markdownSource.lowercased()

            for word in queryWords {
                let matches = Task {
                    await indexingManager.searchInIndex(word: word)
                }

                if titleLower.contains(word) {
                    score += 10
                }
                if contentLower.contains(word) {
                    score += 2
                    if let range = contentLower.range(of: word) {
                        let start = contentLower.distance(from: contentLower.startIndex, to: range.lowerBound)
                        let excerptStart = max(0, start - 30)
                        let excerptEnd = min(doc.markdownSource.count, start + word.count + 60)
                        let prefixIdx = doc.markdownSource.index(doc.markdownSource.startIndex, offsetBy: excerptStart)
                        let suffixIdx = doc.markdownSource.index(doc.markdownSource.startIndex, offsetBy: excerptEnd)
                        snippet = "..." + doc.markdownSource[prefixIdx..<suffixIdx] + "..."
                    }
                }
            }

            if score > 0 {
                results.append(SearchResult(document: doc, score: score, snippet: snippet.isEmpty ? doc.markdownSource.prefix(80) + "..." : snippet))
            }
        }

        return results.sorted { $0.score > $1.score }
    }
}
