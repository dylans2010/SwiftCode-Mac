import Foundation
import SwiftData

public actor AIContextManager {
    private let projectID: UUID

    public init(projectID: UUID) {
        self.projectID = projectID
    }

    public struct AIContextPayload: Sendable {
        public let projectID: UUID
        public let contextText: String
        public let tokensCount: Int
    }

    public func buildContext(for documents: [Document]) async -> AIContextPayload {
        var contextStr = ""
        for doc in documents {
            contextStr += "=== Document: \(doc.title) (\(doc.moduleKindRaw)) ===\n"
            contextStr += doc.markdownSource + "\n\n"
        }
        let tokens = contextStr.count / 4
        return AIContextPayload(projectID: projectID, contextText: contextStr, tokensCount: tokens)
    }
}
