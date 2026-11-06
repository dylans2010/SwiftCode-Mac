import Foundation

public struct GitRemote: Identifiable, Sendable, Codable {
    public var id: String { name }
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}
