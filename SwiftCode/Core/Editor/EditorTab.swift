import Foundation

public struct EditorTab: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let fileURL: URL

    public init(fileURL: URL) {
        self.id = UUID()
        self.fileURL = fileURL
    }
}
