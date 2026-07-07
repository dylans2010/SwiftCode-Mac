import Foundation
import SwiftUI
import Observation

public struct CodePatch: Identifiable, Sendable {
    public let id: UUID
    public let filePath: String
    public let diff: String

    public init(id: UUID = UUID(), filePath: String, diff: String) {
        self.id = id
        self.filePath = filePath
        self.diff = diff
    }
}

@Observable
@MainActor
public final class CodePatchEngine {
    public static let shared = CodePatchEngine()

    public var pendingPatches: [CodePatch] = []

    private init() {}

    public func applyPatch(_ patch: CodePatch) throws {
        // Implementation stub
        pendingPatches.removeAll { $0.id == patch.id }
    }

    public func rejectPatch(_ patch: CodePatch) {
        pendingPatches.removeAll { $0.id == patch.id }
    }
}
