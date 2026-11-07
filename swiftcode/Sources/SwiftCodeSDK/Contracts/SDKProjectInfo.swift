import Foundation

public struct SDKProjectInfo: Codable, Sendable {
    public let id: String

    public let name: String

    public let rootPath: String

    public let isOpen: Bool

    public init(id: String, name: String, rootPath: String, isOpen: Bool = true) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.isOpen = isOpen
    }
}
