import Foundation

// MARK: - SDKCodeFileNode
//
// One node in the code editor's file tree. A VALUE TYPE with lazy
// children: `children` is `nil` until the directory has been enumerated
// (`isDirectory == false` nodes always have `nil` children). The tree
// owner expands a node by loading its children and swapping in a new
// value via `withChildren(_:)`; the view layer never blocks on I/O to
// render the tree.
//
// `isExpanded` is UI state kept on the node so expansion survives child
// reloads; collapsing keeps the loaded children so re-expanding is free.

public struct SDKCodeFileNode: Identifiable, Sendable, Hashable {
    /// Identity and URL are one and the same: a path uniquely identifies a
    /// node within one project tree.
    public var id: String { url.path }

    public let url: URL
    public let isDirectory: Bool

    /// Loaded children, or `nil` when the directory has not been
    /// enumerated yet (lazy). Always `nil` for files.
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
        // Guard the lazy-loading invariant: files never carry children.
        self.children = isDirectory ? children : nil
        self.isExpanded = isExpanded
    }

    /// Filename shown in the tree, e.g. "ContentView.swift".
    public var name: String { url.lastPathComponent }

    /// `true` when this is a directory whose children have not been
    /// enumerated yet — the tree renders this as expandable-with-spinner.
    public var needsLoading: Bool { isDirectory && children == nil }

    /// Returns a copy with enumerated children attached.
    public func withChildren(_ newChildren: [SDKCodeFileNode]) -> SDKCodeFileNode {
        SDKCodeFileNode(url: url, isDirectory: isDirectory, children: newChildren, isExpanded: isExpanded)
    }

    /// Returns a copy with the expansion state toggled. Loaded children
    /// are preserved so collapsing and re-expanding does not re-enumerate.
    public func toggledExpanded() -> SDKCodeFileNode {
        SDKCodeFileNode(url: url, isDirectory: isDirectory, children: children, isExpanded: !isExpanded)
    }
}
