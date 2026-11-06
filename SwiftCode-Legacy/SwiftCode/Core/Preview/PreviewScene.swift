import Foundation
import Observation

// @unchecked Sendable is safe here because PreviewScene is an @Observable class whose properties
// are mutated and accessed on a single thread (typically the Main Actor) as part of UI observation,
// and state tracking is managed dynamically by the Observation framework.
@Observable
public final class PreviewScene: Identifiable, @unchecked Sendable {
    public let id: UUID
    public var name: String
    public var rootNode: PreviewSceneNode

    public init(id: UUID = UUID(), name: String = "Untitled Scene", rootNode: PreviewSceneNode) {
        self.id = id
        self.name = name
        self.rootNode = rootNode
    }
}

// @unchecked Sendable is safe here because PreviewSceneNode is an @Observable class whose properties
// are mutated and accessed on a single thread (typically the Main Actor) as part of UI observation,
// and state tracking is managed dynamically by the Observation framework.
@Observable
public final class PreviewSceneNode: Identifiable, @unchecked Sendable {
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
