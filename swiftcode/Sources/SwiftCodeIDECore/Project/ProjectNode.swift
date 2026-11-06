// Adapted from SwiftCode-Legacy SwiftCode/Core/Project/ProjectNode.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
import Foundation

public struct ProjectNode: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let kind: Kind
    public var children: [ProjectNode]?

    public enum Kind: Sendable {
        case file
        case folder
    }

    public init(url: URL, kind: Kind, children: [ProjectNode]? = nil) {
        self.id = url.path
        self.url = url
        self.kind = kind
        self.children = children
    }
}
