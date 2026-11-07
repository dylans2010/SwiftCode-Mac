import AppKit
import YcodeIDECore

public enum EditorOptionsMenu {
    static let addEditorID = NSToolbarItem.Identifier("addEditor")
    static let editorOptionsID = NSToolbarItem.Identifier("editorOptions")

    public static let rightGroup = ["addEditor", "editorOptions", "editorModes"]

    static var items: [MenuItemSpec] {
        let u = CommandTable.unavailable
        return [
            .submenu("Layout", [
                .command(.init("Editor Pane On Right", "", [], "splitEditor:")),
                .command(.init("Editor Pane Below", "", [], "splitEditorBelow:")),
            ]),
            .separator,
            .command(.init("Inline Comparison", "", [], "showInlineComparison:")),
            .command(.init("Side By Side Comparison", "", [], "showSideBySideComparison:")),
            .separator,
            .command(.init("Minimap", "", [], "toggleMinimap:")),
            .command(.init("Authors", "", [], "toggleAuthors:")),
            u("Code Coverage"),
            .separator,
            .command(.init("Invisibles", "", [], "toggleInvisibles:")),
            .command(.init("Scope Guides", "", [], "toggleScopeGuides:")),
            .command(.init("Wrap Lines", "", [], "toggleWrapLines:")),
            .separator,
            .command(.init("Choose Workspace Theme…", "", [], "chooseTheme:")),
        ]
    }

    static var addItems: [MenuItemSpec] {
        [
            .command(.init("Add Editor Tab", "", [], "newTab:")),
            .command(.init("Add Editor Pane on Right", "", [], "splitEditor:")),
            .command(.init("Add Editor Pane Below", "", [], "splitEditorBelow:")),
        ]
    }

    @MainActor public static func menu() -> NSMenu { MainMenu.menu("Adjust Editor Options", items) }
    @MainActor public static func addMenu() -> NSMenu { MainMenu.menu("Add Editor Tabs or Editor Panes", addItems) }
}

enum ToolbarGlass {
    static var glass: Bool { if #available(macOS 26, *) { return true }; return false }
    static var leftPanesSegment: CGFloat { glass ? 31.5 : 38 }
    static var pairSegment: CGFloat { glass ? 30 : 0 }
    static var editorModesSegment: CGFloat { glass ? 35 : 38 }
}

extension WorkspaceWindowController {
    func rightGroupToolbarItem(_ id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        func menuItem(_ symbol: String, _ label: String, _ tip: String, _ menu: NSMenu) -> NSToolbarItem {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.label = label
            item.toolTip = tip
            item.menu = menu
            item.showsIndicator = false
            item.visibilityPriority = .high
            return item
        }
        switch id {
        case EditorOptionsMenu.addEditorID:
            return menuItem("plus.rectangle.on.rectangle", "Add Editor", "Add Editor Tabs or Editor Panes", EditorOptionsMenu.addMenu())
        case EditorOptionsMenu.editorOptionsID:
            return menuItem("line.3.horizontal", "Editor Options", "Adjust Editor Options", EditorOptionsMenu.menu())
        default:
            return nil
        }
    }

    public static func inspectorToggleTitle(shown: Bool) -> String { shown ? "Hide Inspector" : "Show Inspector" }

    func updateAreaToggleTitles() {
        guard let inspectorItem, let debugItem else { return }
        if let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.inspectorToggleID }) {
            let t = Self.inspectorToggleTitle(shown: !inspectorItem.isCollapsed)
            if item.label != t { item.label = t; item.toolTip = t }
        }
        debugArea.setDebugAreaShown(!debugItem.isCollapsed)
    }

    public var inspectorToggleItemTitle: String? {
        window?.toolbar?.items.first { $0.itemIdentifier == Self.inspectorToggleID }?.label
    }

    func observeToolbarRoom() {
        let center = NotificationCenter.default
        leftAreaObservation.tokens.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToolbar() }
        })
        leftAreaObservation.tokens.append(center.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: mainSplit.splitView,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleToolbarFit() }
        })
        leftAreaObservation.tokens.append(inspectorItem.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateAreaToggleTitles()
                self?.scheduleToolbarFit()
            }
        })
        leftAreaObservation.tokens.append(debugItem.observe(\.isCollapsed, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateAreaToggleTitles() }
        })
        updateEditorModesPullDown()
        updateAreaToggleTitles()
    }

    func scheduleToolbarFit() {
        guard !toolbarControls.fitScheduled else { return }
        toolbarControls.fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.toolbarControls.fitScheduled = false
                self.fitToolbar()
            }
        }
    }

    public var toolbarFit: ToolbarFit { toolbarControls.fit }

    public var overflowedToolbarItems: [String] {
        guard let toolbar = window?.toolbar else { return [] }
        let visible = Set((toolbar.visibleItems ?? []).map(\.itemIdentifier))
        return toolbar.items.filter { !$0.isHidden }.map(\.itemIdentifier)
            .filter { !visible.contains($0) && !Self.toolbarSpacers.contains($0) }.map(\.rawValue)
    }
    static let toolbarSpacers: Set<NSToolbarItem.Identifier> = [.flexibleSpace, .space, .sidebarTrackingSeparator, FlushSidebar.trackingSeparatorID,
                                                                 .inspectorTrackingSeparator]

    public func fitToolbar() {
        guard let window, let frame = window.contentView?.superview, window.toolbar != nil, !toolbarControls.fitting else { return }
        toolbarControls.fitting = true
        defer { toolbarControls.fitting = false }
        func fits(_ f: ToolbarFit) -> Bool {
            apply(f)
            frame.layoutSubtreeIfNeeded()
            return f.accepts(overflowed: overflowedToolbarItems)
        }
        let steps = ToolbarFit.steps(activityNatural: activityView.naturalWidth)
        for f in steps where fits(f) {
            toolbarControls.fit = f
            return
        }
        toolbarControls.fit = steps.last ?? ToolbarFit()
        apply(toolbarControls.fit)
    }

    func apply(_ f: ToolbarFit) {
        setSchemeGlyphsOnly(f.schemeGlyphsOnly)
        activityView.maximumWidth = f.activityWidth ?? .greatestFiniteMagnitude
    }

    func setSchemeGlyphsOnly(_ glyphsOnly: Bool) {
        for p in [schemePopUp, destinationPopUp] {
            let position: NSControl.ImagePosition = glyphsOnly ? .imageOnly : .imageLeading
            if p.imagePosition != position {
                p.imagePosition = position
                p.invalidateIntrinsicContentSize()
            }
            let tip = glyphsOnly ? p.titleOfSelectedItem : nil
            if p.toolTip != tip { p.toolTip = tip }
        }
        if #available(macOS 26, *), let stack = schemePopUp.superview as? NSStackView {
            let side: CGFloat = glyphsOnly ? 14 : 8
            if stack.edgeInsets.left != side { stack.edgeInsets = NSEdgeInsets(top: 0, left: side, bottom: 0, right: side) }
            stack.spacing = glyphsOnly ? 4 : 0
        }
    }

    public var schemeShowsGlyphsOnly: Bool { schemePopUp.imagePosition == .imageOnly }

    public var schemeCapsuleWidth: CGFloat {
        guard let v = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.schemeID })?.view else { return 0 }
        v.layoutSubtreeIfNeeded()
        return v.fittingSize.width
    }

    func updateEditorModesPullDown() {
        guard let item = window?.toolbar?.items.first(where: { $0.itemIdentifier == Self.editorModesID }) else { return }
        item.menuFormRepresentation = editorModesMenuItem()
    }

    func editorModesMenuItem() -> NSMenuItem {
        let mode = activeEditorMode
        let symbols = WorkspaceChrome.editorModes.symbols
        let titles = ["Canvas", "Assistant", "Code Review"]
        let menu = NSMenu(title: "Editor Modes")
        for m in EditorMode.allCases {
            let i = NSMenuItem(title: titles[m.rawValue], action: #selector(editorModeMenuChosen(_:)), keyEquivalent: "")
            i.target = self
            i.tag = m.rawValue
            if symbols.indices.contains(m.rawValue) { i.image = NSImage(systemSymbolName: symbols[m.rawValue], accessibilityDescription: nil) }
            i.state = m == mode ? .on : .off
            menu.addItem(i)
        }
        let top = NSMenuItem(title: "Editor Modes", action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }

    @objc func editorModeMenuChosen(_ item: NSMenuItem) {
        if let m = EditorMode(rawValue: item.tag) { setEditorMode(m) }
        updateToolbarState()
    }
}

extension WorkspaceChrome.ToolbarItem {
    @MainActor func images(descriptions: [String]? = nil) -> [NSImage] {
        zip(symbols, descriptions ?? toolTips).map { NSImage(systemSymbolName: $0, accessibilityDescription: $1)! }
    }
    @MainActor var images: [NSImage] { images() }
}
