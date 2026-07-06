import Foundation
import SwiftUI

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

public final class CodePatchEngine: ObservableObject {
    public static let shared = CodePatchEngine()

    @Published public var pendingPatches: [CodePatch] = []

    private init() {}

    public func applyPatch(_ patch: CodePatch) throws {
        // Implementation stub
        pendingPatches.removeAll { $0.id == patch.id }
    }

    public func rejectPatch(_ patch: CodePatch) {
        pendingPatches.removeAll { $0.id == patch.id }
    }
}
