import AppKit

@MainActor
enum FlushSidebar {
    static var forced: Bool?

    static var isActive: Bool {
        forced ?? (ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26)
    }

    static let holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)

    static func item(for content: NSViewController, overhang: CGFloat = 0) -> NSSplitViewItem {
        guard isActive else { return NSSplitViewItem(sidebarWithViewController: content) }
        let item = NSSplitViewItem(viewController: FlushSidebarController(content: content, overhang: overhang))
        item.canCollapse = true
        item.canCollapseFromWindowResize = true
        item.holdingPriority = holdingPriority
        return item
    }

    static func position(forWidth width: CGFloat, of item: NSSplitViewItem) -> CGFloat {
        width - ((item.viewController as? FlushSidebarController)?.overhang ?? 0)
    }

    static var separatorIdentifier: NSToolbarItem.Identifier { isActive ? trackingSeparatorID : .sidebarTrackingSeparator }
    nonisolated static let trackingSeparatorID = NSToolbarItem.Identifier("SwiftCodeSidebarTrackingSeparator")

    static func trackingSeparator(_ id: NSToolbarItem.Identifier, splitView: NSSplitView) -> NSToolbarItem? {
        guard id == trackingSeparatorID else { return nil }
        return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView, dividerIndex: 0)
    }
}

@MainActor
final class FlushSidebarController: NSViewController {
    let content: NSViewController
    let overhang: CGFloat

    init(content: NSViewController, overhang: CGFloat) {
        self.content = content
        self.overhang = overhang
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = NSView()
        root.clipsToBounds = false
        view = root
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        addChild(content)
        for v in [background, content.view] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: root.topAnchor),
                v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: overhang),
            ])
        }
    }
}
