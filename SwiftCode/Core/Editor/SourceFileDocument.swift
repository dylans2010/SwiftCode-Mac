import Foundation

public struct SourceFileDocument: Identifiable, Sendable, Codable {
    public let id: UUID
    public let url: URL
    public var content: String
    public var isDirty: Bool
    public let language: SourceLanguage
    public var lastDiskModificationDate: Date

    public init(url: URL, content: String, lastDiskModificationDate: Date) {
        self.id = UUID()
        self.url = url
        self.content = content
        self.isDirty = false
        self.language = SourceLanguage.from(url: url)
        self.lastDiskModificationDate = lastDiskModificationDate
    }
}
