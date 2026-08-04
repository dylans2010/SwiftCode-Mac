import AppKit
import SwiftUI

@MainActor
public final class VirtualizationSplitViewController: NSSplitViewController {
    private var sidebarItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // Left: Sidebar view controller
        let sidebarVC = NSHostingController(rootView: VirtualizationSidebarView())
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 10
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        // Right: Main Area view controller
        let mainView = VirtualizationWorkspaceView()
        let mainVC = NSHostingController(rootView: mainView)
        mainVC.sizingOptions = []
        mainVC.view.autoresizingMask = [.width, .height]
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 680
        mainItem.holdingPriority = .defaultLow - 10
        self.mainItem = mainItem
        addSplitViewItem(mainItem)
    }
}
