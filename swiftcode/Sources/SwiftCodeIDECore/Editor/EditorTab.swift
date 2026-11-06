// Adapted from SwiftCode-Legacy SwiftCode/Core/Editor/EditorTab.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct EditorTab: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let fileURL: URL

    public init(fileURL: URL) {
        self.id = UUID()
        self.fileURL = fileURL
    }
}
