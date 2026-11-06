import AppKit
import SwiftUI

// MARK: - Native Sidebar Selection state for Visual UI Builder
@Observable
@MainActor
public final class VisualUIBuilderSidebarState {
    public static let shared = VisualUIBuilderSidebarState()
    public var selectedIndex: Int = 0 // 0 = Library, 1 = Hierarchy
    private init() {}
}

// MARK: - Visual UI Builder Sidebar Node
public final class VisualUIBuilderSidebarNode: NSObject {
    public let title: String
    public let icon: String?
    public let tag: Int
    public let isGroup: Bool
    public var children: [VisualUIBuilderSidebarNode] = []

    public init(title: String, icon: String? = nil, tag: Int = 0, isGroup: Bool = false) {
        self.title = title
        self.icon = icon
        self.tag = tag
        self.isGroup = isGroup
    }
}

// MARK: - Native Left Sidebar View Controller for Visual UI Builder
public class VisualUIBuilderSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    public let document: VisualUIDocument

    private var scrollView: NSScrollView?
    private var outlineView: NSOutlineView?
    private var contentContainer: NSView?
    private var hostingView: NSView?
    private var nodes: [VisualUIBuilderSidebarNode] = []

    public init(document: VisualUIDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
        self.nodes = buildSidebarNodes()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let rootVisualEffectView = NSVisualEffectView()
        rootVisualEffectView.material = .sidebar
        rootVisualEffectView.blendingMode = .behindWindow
        rootVisualEffectView.state = .active
        rootVisualEffectView.autoresizingMask = [.width, .height]

        // 1. Setup outline view for category switcher
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView = scroll

        let outline = NSOutlineView()
        outline.headerView = nil
        outline.selectionHighlightStyle = .sourceList
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .custom
        outline.indentationPerLevel = 14
        self.outlineView = outline

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("VisualUIBuilderSidebarColumn"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = self
        outline.delegate = self
        scroll.documentView = outline

        rootVisualEffectView.addSubview(scroll)

        // 2. Setup dynamic hosting content container below the switcher
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        rootVisualEffectView.addSubview(container)
        self.contentContainer = container

        // Setup constraints (OutlineView on top, ContentContainer taking the rest)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: rootVisualEffectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: rootVisualEffectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: rootVisualEffectView.topAnchor, constant: 40),
            scroll.heightAnchor.constraint(equalToConstant: 120), // Compact switcher on top

            container.leadingAnchor.constraint(equalTo: rootVisualEffectView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: rootVisualEffectView.trailingAnchor),
            container.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            container.bottomAnchor.constraint(equalTo: rootVisualEffectView.bottomAnchor)
        ])

        self.view = rootVisualEffectView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        if let outline = outlineView {
            for group in nodes {
                outline.expandItem(group)
            }
            // Select Library (row index 1 because row 0 is Group Header "COMPONENTS")
            outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        }
        updateHostedContent()
    }

    private func buildSidebarNodes() -> [VisualUIBuilderSidebarNode] {
        let group = VisualUIBuilderSidebarNode(title: "COMPONENTS", isGroup: true)
        group.children = [
            VisualUIBuilderSidebarNode(title: "Component Library", icon: "square.grid.2x2", tag: 0),
            VisualUIBuilderSidebarNode(title: "View Hierarchy", icon: "list.bullet.indent", tag: 1),
            VisualUIBuilderSidebarNode(title: "Saved Artboards", icon: "folder.badge.plus", tag: 2)
        ]
        return [group]
    }

    // MARK: - Dynamic Swappable Content Management
    private func updateHostedContent() {
        guard let container = contentContainer else { return }

        // Remove old hosting view if any
        hostingView?.removeFromSuperview()

        // Create new SwiftUI content view based on selection
        let selectedIndex = VisualUIBuilderSidebarState.shared.selectedIndex
        let swiftUIView: AnyView
        if selectedIndex == 0 {
            swiftUIView = AnyView(
                VisualUIComponentLibrary(document: document)
                    .environment(document)
            )
        } else if selectedIndex == 1 {
            swiftUIView = AnyView(
                VisualUIHierarchy(document: document)
                    .environment(document)
            )
        } else {
            swiftUIView = AnyView(
                SavedArtboardsListView(document: document)
                    .environment(document)
            )
        }

        // Host SwiftUI inside NSHostingView
        let newHostingView = NSHostingView(rootView: swiftUIView)
        newHostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(newHostingView)
        self.hostingView = newHostingView

        NSLayoutConstraint.activate([
            newHostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            newHostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            newHostingView.topAnchor.constraint(equalTo: container.topAnchor),
            newHostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return nodes.count
        }
        if let node = item as? VisualUIBuilderSidebarNode {
            return node.children.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return nodes[index]
        }
        guard let node = item as? VisualUIBuilderSidebarNode else { return VisualUIBuilderSidebarNode(title: "") }
        return node.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? VisualUIBuilderSidebarNode {
            return node.isGroup
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let node = item as? VisualUIBuilderSidebarNode {
            return node.isGroup
        }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let node = item as? VisualUIBuilderSidebarNode {
            return !node.isGroup
        }
        return true
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let node = item as? VisualUIBuilderSidebarNode, node.isGroup {
            return 24
        }
        return 28
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? VisualUIBuilderSidebarNode else { return nil }

        if node.isGroup {
            let identifier = NSUserInterfaceItemIdentifier("VisualUIBuilderSidebarHeaderView")
            var textField = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            if textField == nil {
                textField = NSTextField(labelWithString: node.title)
                textField?.identifier = identifier
                textField?.font = .systemFont(ofSize: 10, weight: .bold)
                textField?.textColor = .headerTextColor
            } else {
                textField?.stringValue = node.title
            }
            return textField
        } else {
            let identifier = NSUserInterfaceItemIdentifier("VisualUIBuilderSidebarCell")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? VisualUIBuilderSidebarCellView
            if cell == nil {
                cell = VisualUIBuilderSidebarCellView(frame: .zero)
                cell?.identifier = identifier
            }

            cell?.textField?.stringValue = node.title
            if let iconName = node.icon {
                if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    cell?.iconView.image = image
                } else {
                    cell?.iconView.image = nil
                }
            } else {
                cell?.iconView.image = nil
            }
            cell?.iconView.contentTintColor = .controlAccentColor

            return cell
        }
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline = outlineView else { return }
        let selectedRow = outline.selectedRow
        if selectedRow >= 0, let node = outline.item(atRow: selectedRow) as? VisualUIBuilderSidebarNode {
            VisualUIBuilderSidebarState.shared.selectedIndex = node.tag
            updateHostedContent()
        }
    }
}

// MARK: - Native Sidebar Custom Cell
class VisualUIBuilderSidebarCellView: NSTableCellView {
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 12)
        text.textColor = .labelColor
        addSubview(text)
        self.textField = text

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
