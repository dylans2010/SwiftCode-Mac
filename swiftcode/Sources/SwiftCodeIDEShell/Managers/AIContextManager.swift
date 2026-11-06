// AIContextManager.swift
//
// Ported from Legacy `SwiftCode/Views/Utilities/NSPersonalDocumentation/Managers/AIContextManager.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: standalone buildContext(for:) returning a context payload; AIContextPayload type; token-count estimate
// References legacy types absent from the destination and from this worklist (wiring/integration gaps): AIContextPayload.
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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
