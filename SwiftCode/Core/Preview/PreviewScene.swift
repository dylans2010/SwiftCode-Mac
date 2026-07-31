import Foundation
import Observation

@Observable
public final class PreviewScene: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var rootNode: PreviewSceneNode

    public init(id: UUID = UUID(), name: String = "Untitled Scene", rootNode: PreviewSceneNode) {
        self.id = id
        self.name = name
        self.rootNode = rootNode
    }
}

@Observable
public final class PreviewSceneNode: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var typeString: String
    public var properties: [String: String]
    public var children: [PreviewSceneNode]
    public var isHidden: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        typeString: String,
        properties: [String: String] = [:],
        children: [PreviewSceneNode] = [],
        isHidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.typeString = typeString
        self.properties = properties
        self.children = children
        self.isHidden = isHidden
    }
}
