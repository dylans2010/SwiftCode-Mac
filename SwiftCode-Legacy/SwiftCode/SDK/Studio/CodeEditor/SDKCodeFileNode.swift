import Foundation

public struct SDKCodeFileNode: Identifiable, Sendable, Hashable {
    public var id: String { url.path }

    public let url: URL
    public let isDirectory: Bool

    public let children: [SDKCodeFileNode]?

    public let isExpanded: Bool

    public init(
        url: URL,
        isDirectory: Bool,
        children: [SDKCodeFileNode]? = nil,
        isExpanded: Bool = false
    ) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = isDirectory ? children : nil
        self.isExpanded = isExpanded
    }

    public var name: String { url.lastPathComponent }

    public var needsLoading: Bool { isDirectory && children == nil }

    public func withChildren(_ newChildren: [SDKCodeFileNode]) -> SDKCodeFileNode {
        SDKCodeFileNode(url: url, isDirectory: isDirectory, children: newChildren, isExpanded: isExpanded)
    }

    public func toggledExpanded() -> SDKCodeFileNode {
        SDKCodeFileNode(url: url, isDirectory: isDirectory, children: children, isExpanded: !isExpanded)
    }
}
