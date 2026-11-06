import AppKit
import SwiftUI

// MARK: - Database Sidebar Node
public final class DatabaseSidebarNode: NSObject {
    public let title: String
    public let icon: String?
    public let section: DatabaseSection?
    public let isGroup: Bool
    public var children: [DatabaseSidebarNode] = []

    public init(title: String, icon: String? = nil, section: DatabaseSection? = nil, isGroup: Bool = false) {
        self.title = title
        self.icon = icon
        self.section = section
        self.isGroup = isGroup
    }
}

// MARK: - Native Left Sidebar View Controller for Database Explorer
public class DatabaseExplorerSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private var scrollView: NSScrollView?
    private var outlineView: NSOutlineView?
    private var nodes: [DatabaseSidebarNode] = []

    public init() {
        super.init(nibName: nil, bundle: nil)
        self.nodes = buildSidebarNodes()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        self.scrollView = scroll

        let outline = NSOutlineView()
        outline.autoresizingMask = [.width]
        outline.headerView = nil
        outline.selectionHighlightStyle = .sourceList
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .custom
        outline.indentationPerLevel = 14
        self.outlineView = outline

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DatabaseSidebarColumn"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = self
        outline.delegate = self

        scroll.documentView = outline
        visualEffectView.addSubview(scroll)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 40),
            scroll.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        self.view = visualEffectView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        if let outline = outlineView {
            for group in nodes {
                outline.expandItem(group)
            }
            // Select row for Dashboard (row index 1 because row 0 is Group Header "WORKSPACE")
            outline.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        }
    }

    private func buildSidebarNodes() -> [DatabaseSidebarNode] {
        var groups: [DatabaseSidebarNode] = []

        // 1. Workspace
        let workspace = DatabaseSidebarNode(title: "WORKSPACE", isGroup: true)
        workspace.children = [
            DatabaseSidebarNode(title: "Dashboard", icon: "square.grid.2x2", section: .dashboard),
            DatabaseSidebarNode(title: "Tables & Views", icon: "tablecells", section: .tables),
            DatabaseSidebarNode(title: "Schema Designer", icon: "point.topleft.down.to.point.bottomright.curvepath", section: .schemaDesigner)
        ]
        groups.append(workspace)

        // 2. Query & AI
        let queryAI = DatabaseSidebarNode(title: "QUERY & AI", isGroup: true)
        queryAI.children = [
            DatabaseSidebarNode(title: "SQL Editor", icon: "terminal", section: .sqlEditor),
            DatabaseSidebarNode(title: "AI Assistant", icon: "sparkles", section: .aiAssistant),
            DatabaseSidebarNode(title: "Templates", icon: "square.stack.3d.up", section: .templates)
        ]
        groups.append(queryAI)

        // 3. Maintenance
        let maintenance = DatabaseSidebarNode(title: "MAINTENANCE", isGroup: true)
        maintenance.children = [
            DatabaseSidebarNode(title: "Migrations", icon: "arrow.triangle.2.circlepath", section: .migrations),
            DatabaseSidebarNode(title: "Backups", icon: "archivebox", section: .backups),
            DatabaseSidebarNode(title: "Import & Export", icon: "arrow.up.and.down.and.arrow.left.and.right", section: .importExport)
        ]
        groups.append(maintenance)

        // 4. Performance & Setup
        let performanceSetup = DatabaseSidebarNode(title: "PERFORMANCE & SETUP", isGroup: true)
        performanceSetup.children = [
            DatabaseSidebarNode(title: "Performance", icon: "gauge.with.needle", section: .performance),
            DatabaseSidebarNode(title: "Logs & Statistics", icon: "doc.text", section: .logs),
            DatabaseSidebarNode(title: "Settings", icon: "gearshape", section: .settings)
        ]
        groups.append(performanceSetup)

        return groups
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return nodes.count
        }
        if let node = item as? DatabaseSidebarNode {
            return node.children.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return nodes[index]
        }
        guard let node = item as? DatabaseSidebarNode else { return DatabaseSidebarNode(title: "") }
        return node.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? DatabaseSidebarNode {
            return node.isGroup
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let node = item as? DatabaseSidebarNode {
            return node.isGroup
        }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let node = item as? DatabaseSidebarNode {
            return !node.isGroup
        }
        return true
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let node = item as? DatabaseSidebarNode, node.isGroup {
            return 24
        }
        return 28
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? DatabaseSidebarNode else { return nil }

        if node.isGroup {
            let identifier = NSUserInterfaceItemIdentifier("DatabaseSidebarHeaderView")
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
            let identifier = NSUserInterfaceItemIdentifier("DatabaseSidebarCell")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? DatabaseSidebarCellView
            if cell == nil {
                cell = DatabaseSidebarCellView(frame: .zero)
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
        if selectedRow >= 0, let node = outline.item(atRow: selectedRow) as? DatabaseSidebarNode, let section = node.section {
            DatabaseObservableState.shared.selectedSection = section
            DatabaseSplitViewState.shared.selectedSection = section
        }
    }
}

// MARK: - Native Sidebar Custom Cell for Database
class DatabaseSidebarCellView: NSTableCellView {
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
