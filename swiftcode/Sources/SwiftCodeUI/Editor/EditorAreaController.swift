import AppKit
import SwiftCodeIDECore

@MainActor
public final class EditorAreaController: NSViewController {
    @MainActor public final class Tab {
        public internal(set) var editors: [SourceEditorController]
        public internal(set) var sideBySide = true
        public internal(set) var focused = 0
        public internal(set) weak var assistant: SourceEditorController?
        public internal(set) var isPinned = false
        let controller = NSSplitViewController()
        var split: NSSplitView { controller.splitView }

        init(editor: SourceEditorController) { editors = [editor] }
        public var focusedEditor: SourceEditorController { editors[min(focused, editors.count - 1)] }
    }

    public private(set) var tabs: [Tab] = []
    public private(set) var selectedTab = 0
    public var configure: ((SourceEditorController) -> Void)?
    public var onFocusChange: ((SourceEditorController) -> Void)?

    private let tabBar = NSStackView()
    private var tabBarHeight: NSLayoutConstraint!
    private var contentUnderToolbar: NSLayoutConstraint!
    private var contentBelowTabs: NSLayoutConstraint!
    private let content = NSView()

    public init(first: SourceEditorController) {
        super.init(nibName: nil, bundle: nil)
        tabs = [Tab(editor: first)]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public var tab: Tab { tabs[selectedTab] }
    public var showsTabBar = false { didSet { reloadTabBar() } }
    public var isTabBarVisible: Bool { EditorTabPolicy.isBarVisible(shown: showsTabBar, tabCount: tabs.count) }
    public private(set) var hoveredTab: Int? { didSet { if hoveredTab != oldValue { updateCloseButtons() } } }
    public var onCloseTabRequest: ((Int) -> Void)?
    public var groupPath: ((URL) -> String)?

    public func togglePin() {
        tab.isPinned.toggle()
        reloadTabBar()
    }
    public var allEditors: [SourceEditorController] { tabs.flatMap(\.editors) }
    public var focusedEditor: SourceEditorController { tab.focusedEditor }

    public override func loadView() {
        let root = NSView()
        tabBar.orientation = .horizontal
        tabBar.spacing = 0
        tabBar.distribution = .fillEqually
        for v in [tabBar, content] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor), tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor), tabBarHeight,
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor), content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])
        contentUnderToolbar = content.topAnchor.constraint(equalTo: root.topAnchor)
        contentBelowTabs = content.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
        contentUnderToolbar.isActive = true
        view = root
        for e in tabs[0].editors { prepare(e, in: tabs[0]) }
        showSelected()
    }

    private func prepare(_ e: SourceEditorController, in tab: Tab) {
        e.onActivate = { [weak self, weak e, weak tab] in
            guard let self, let e, let tab, let i = tab.editors.firstIndex(where: { $0 === e }) else { return }
            if tab.focused != i { tab.focused = i; self.onFocusChange?(e) }
        }
    }

    public var canvasPlacement: CanvasPlacement? {
        guard canvas != nil else { return nil }
        return tab.editors.count == 1 ? canvasLayout ?? CanvasPlacement.placement(forWidth: isViewLoaded ? content.bounds.width : 0)
            : (tab.sideBySide ? .beside : .below)
    }

    public var canvasLayout: CanvasPlacement? {
        didSet {
            guard oldValue != canvasLayout, isViewLoaded else { return }
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
        }
    }

    func layout(_ t: Tab) {
        t.split.isVertical = canvas != nil && t.editors.count == 1 && t === tab ? canvasPlacement == .beside : t.sideBySide
        t.split.dividerStyle = .thin
        for item in t.controller.splitViewItems { t.controller.removeSplitViewItem(item) }
        for e in t.editors {
            let item = NSSplitViewItem(viewController: e)
            item.holdingPriority = NSLayoutConstraint.Priority(250)
            t.controller.addSplitViewItem(item)
        }
        if let c = canvas {
            if c.parent != nil && c.parent !== t.controller { c.removeFromParent() }
            let item = NSSplitViewItem(viewController: c)
            item.holdingPriority = NSLayoutConstraint.Priority(250)
            t.controller.addSplitViewItem(item)
        }
    }

    func showSelected() {
        guard isViewLoaded else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        let t = tab
        layout(t)
        if t.controller.parent == nil { addChild(t.controller) }
        let sv = t.controller.view
        sv.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sv)
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: content.topAnchor), sv.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sv.leadingAnchor.constraint(equalTo: content.leadingAnchor), sv.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        needsEqualize = true
        view.needsLayout = true
        content.layoutSubtreeIfNeeded()
        if t.split.bounds.width > 0 { equalize(t); needsEqualize = false }
        reloadTabBar()
        updatePaneChrome()
    }

    private var needsEqualize = false

    public override func viewDidLayout() {
        super.viewDidLayout()
        if needsEqualize, tab.split.bounds.width > 0 { needsEqualize = false; equalize(tab) }
        if let p = canvasPlacement, tab.editors.count == 1, (p == .beside) != tab.split.isVertical {
            tab.split.isVertical = p == .beside
            needsEqualize = true
            view.needsLayout = true
        }
    }

    func equalize(_ t: Tab) {
        let n = t.editors.count + (canvas == nil ? 0 : 1)
        guard n > 1 else { return }
        let total = t.split.isVertical ? t.split.bounds.width : t.split.bounds.height
        for i in 0..<(n - 1) { t.split.setPosition(total * CGFloat(i + 1) / CGFloat(n), ofDividerAt: i) }
        t.split.layoutSubtreeIfNeeded()
    }

    public var tabTitles: [String] {
        tabs.map { t in
            if let u = t.focusedEditor.fileURL { return EditorTabPolicy.title(for: u) }
            return t.focusedEditor.pathComponents.last?.0 ?? "Untitled"
        }
    }

    public func reloadTabBar() {
        guard isViewLoaded else { return }
        tabBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        tabBarHeight.constant = isTabBarVisible ? 26 : 0
        contentUnderToolbar.isActive = !isTabBarVisible
        contentBelowTabs.isActive = isTabBarVisible
        guard isTabBarVisible else { return }
        for (i, title) in tabTitles.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(tabClicked(_:)))
            b.tag = i
            b.bezelStyle = .smallSquare
            b.state = i == selectedTab ? .on : .off
            b.setButtonType(.pushOnPushOff)
            b.font = .systemFont(ofSize: 11)
            if let u = tabs[i].focusedEditor.fileURL {
                b.image = NSWorkspace.shared.icon(forFile: u.path)
                b.image?.size = NSSize(width: 14, height: 14)
                b.imagePosition = .imageLeading
                b.toolTip = EditorTabPolicy.toolTip(for: u, groupPath: groupPath?(u))
            }
            if tabs[i].isPinned {
                let pin = NSImageView(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")!)
                pin.translatesAutoresizingMaskIntoConstraints = false
                b.addSubview(pin)
                NSLayoutConstraint.activate([pin.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -6), pin.centerYAnchor.constraint(equalTo: b.centerYAnchor)])
            }
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")!, target: self, action: #selector(closeClicked(_:)))
            close.tag = i
            close.isBordered = false
            close.identifier = NSUserInterfaceItemIdentifier("tab-close")
            close.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(close)
            NSLayoutConstraint.activate([close.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 6), close.centerYAnchor.constraint(equalTo: b.centerYAnchor),
                                         close.widthAnchor.constraint(equalToConstant: 12), close.heightAnchor.constraint(equalToConstant: 12)])
            b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: ["tab": i]))
            tabBar.addArrangedSubview(b)
        }
        updateCloseButtons()
    }

    public var closeButtons: [NSButton] {
        tabBar.arrangedSubviews.compactMap { $0.subviews.first { $0.identifier?.rawValue == "tab-close" } as? NSButton }
    }

    func updateCloseButtons() {
        for (i, c) in closeButtons.enumerated() { c.isHidden = !EditorTabPolicy.showsCloseButton(tab: i, hovered: hoveredTab) }
    }

    public func hover(_ i: Int?) { hoveredTab = i }

    public override func mouseEntered(with event: NSEvent) { hover(event.trackingArea?.userInfo?["tab"] as? Int) }
    public override func mouseExited(with event: NSEvent) {
        if let i = event.trackingArea?.userInfo?["tab"] as? Int, i == hoveredTab { hover(nil) }
    }

    @objc private func tabClicked(_ b: NSButton) { selectTab(b.tag) }
    @objc private func closeClicked(_ b: NSButton) {
        if let onCloseTabRequest { onCloseTabRequest(b.tag) } else { closeTab(at: b.tag) }
    }

    @discardableResult
    public func newTab() -> SourceEditorController {
        defer { reloadTabBar() }
        let e = SourceEditorController()
        configure?(e)
        let t = Tab(editor: e)
        prepare(e, in: t)
        tabs.insert(t, at: selectedTab + 1)
        selectedTab += 1
        showSelected()
        onFocusChange?(e)
        return e
    }

    public func selectTab(_ i: Int) {
        guard tabs.indices.contains(i) else { return }
        selectedTab = i
        showSelected()
        onFocusChange?(focusedEditor)
    }

    public func selectNextTab() { selectTab((selectedTab + 1) % tabs.count) }
    public func selectPreviousTab() { selectTab((selectedTab + tabs.count - 1) % tabs.count) }

    @discardableResult
    public func closeTab() -> Bool { closeTab(at: selectedTab) }

    @discardableResult
    public func closeTab(at i: Int) -> Bool {
        guard tabs.count > 1, tabs.indices.contains(i) else { return false }
        for e in tabs[i].editors { try? e.save() }
        selectedTab = EditorTabPolicy.selectionAfterClosing(i, selected: selectedTab, count: tabs.count)
        tabs.remove(at: i)
        hoveredTab = nil
        showSelected()
        onFocusChange?(focusedEditor)
        return true
    }

    @discardableResult
    public func split(sideBySide: Bool) -> SourceEditorController {
        let t = tab
        let e = SourceEditorController()
        configure?(e)
        prepare(e, in: t)
        if t.editors.count == 1 { t.sideBySide = sideBySide }
        let at = t.assistant != nil && t.focused == t.editors.count - 1 ? t.editors.count - 1 : t.focused + 1
        t.editors.insert(e, at: min(at, t.editors.count))
        t.focused = t.editors.firstIndex { $0 === e }!
        showSelected()
        onFocusChange?(e)
        return e
    }

    @discardableResult
    public func closeFocusedEditor() -> Bool {
        let t = tab
        guard t.editors.count > 1 else { return false }
        let e = t.focusedEditor
        try? e.save()
        if t.assistant === e { t.assistant = nil }
        t.editors.remove(at: t.focused)
        t.focused = max(0, t.focused - 1)
        showSelected()
        onFocusChange?(focusedEditor)
        return true
    }

    @discardableResult
    public func showAssistant() -> SourceEditorController {
        let t = tab
        if let a = t.assistant { return a }
        let e = SourceEditorController()
        configure?(e)
        prepare(e, in: t)
        if t.editors.count == 1 { t.sideBySide = true }
        e.showsCloseButton = true
        t.editors.append(e)
        t.assistant = e
        showSelected()
        return e
    }

    public func hideAssistant() {
        let t = tab
        guard let a = t.assistant, let i = t.editors.firstIndex(where: { $0 === a }) else { return }
        try? a.save()
        t.editors.remove(at: i)
        t.assistant = nil
        t.focused = min(t.focused, t.editors.count - 1)
        showSelected()
    }

    public private(set) var canvas: NSViewController?

    public func showCanvas(_ c: NSViewController) {
        canvas = c
        if isViewLoaded { showSelected() }
    }

    public func hideCanvas() {
        canvas = nil
        if isViewLoaded { showSelected() }
    }

    public func withFocus<T>(_ e: SourceEditorController, _ body: () -> T) -> T {
        let t = tab
        guard let i = t.editors.firstIndex(where: { $0 === e }) else { return body() }
        let old = t.focused
        t.focused = i
        defer { t.focused = old }
        return body()
    }

    public func focus(_ e: SourceEditorController) {
        if let i = tab.editors.firstIndex(where: { $0 === e }) { tab.focused = i; onFocusChange?(e) }
    }
}
