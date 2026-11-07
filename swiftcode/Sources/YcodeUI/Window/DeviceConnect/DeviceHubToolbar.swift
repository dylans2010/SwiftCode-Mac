import AppKit
import YcodeDeviceModel
import YcodeDeviceUI

@MainActor
final class DeviceHubToolbar: NSObject, NSToolbarDelegate, NSMenuDelegate, NSToolbarItemValidation {
    unowned let owner: DevicesController
    private weak var zoomGroup: NSToolbarItemGroup?
    private weak var tabGroup: NSToolbarItemGroup?
    private weak var captureGroup: NSToolbarItemGroup?
    private weak var filterItem: NSMenuToolbarItem?
    private let addMenu = NSMenu(title: "Add Device")
    private let filterMenu = NSMenu(title: "Filter")
    private let moreMenu = NSMenu(title: "More Actions")

    static let add = NSToolbarItem.Identifier("hub.addDevice")
    static let filter = NSToolbarItem.Identifier("hub.filter")
    static let captureGroup = NSToolbarItem.Identifier("hub.captureGroup")
    static let resize = NSToolbarItem.Identifier("hub.resizeMode")
    static let tabSymbols = ["slider.horizontal.3", "doc.text", "info"]
    static let resizeHelp = "Enter resize mode (not available: SwiftCode’s simulator does not resize apps yet)"
    static let zoom = NSToolbarItem.Identifier("hub.zoom")
    static let open = NSToolbarItem.Identifier("hub.openInNewWindow")
    static let more = NSToolbarItem.Identifier("hub.more")
    static let tabs = NSToolbarItem.Identifier("hub.inspectorTabs")
    static let headset = NSToolbarItem.Identifier("hub.headset")

    init(owner: DevicesController) {
        self.owner = owner
        super.init()
        for m in [addMenu, filterMenu, moreMenu] { m.delegate = self }
    }

    func install(on w: NSWindow) {
        let t = NSToolbar(identifier: "SwiftCodeDeviceHub")
        t.delegate = self
        t.displayMode = .iconOnly
        t.allowsUserCustomization = false
        w.toolbar = t
    }

    static let order: [NSToolbarItem.Identifier] = [.flexibleSpace, add, filter, .toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace,
                                                    headset, captureGroup, zoom, open, more, .inspectorTrackingSeparator, .flexibleSpace, tabs]

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        if #available(macOS 14.0, *) { return Self.order }
        return Self.order.filter { $0 != .inspectorTrackingSeparator }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func image(_ n: String, _ l: String) -> NSImage? { NSImage(systemSymbolName: n, accessibilityDescription: l) }
        switch id {
        case Self.add:
            let i = NSMenuToolbarItem(itemIdentifier: id)
            i.image = image("plus", "Add Device")
            i.label = "Add Device"
            i.toolTip = "Add Device"
            i.showsIndicator = false
            i.menu = addMenu
            return i
        case Self.filter:
            let i = NSMenuToolbarItem(itemIdentifier: id)
            i.image = image("line.3.horizontal.decrease", "Filter")
            i.label = "Filter"
            i.toolTip = "Filter"
            i.showsIndicator = false
            i.menu = filterMenu
            filterItem = i
            updateFilterLook()
            return i
        case .toggleSidebar:
            return nil
        case Self.captureGroup:
            let labels = ["Capture Keyboard", "Enter resize mode"]
            let images = ["keyboard", "rectangle.inset.filled"].enumerated().compactMap { image($0.element, labels[$0.offset]) }
            let g = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .selectAny, labels: labels,
                                       target: self, action: #selector(captureGroupChosen(_:)))
            g.subitems[0].toolTip = "Capture Keyboard"
            g.subitems[1].toolTip = Self.resizeHelp
            g.subitems[1].autovalidates = false
            g.subitems[1].isEnabled = false
            g.subitems[1].action = nil
            g.label = "Capture Keyboard"
            g.controlRepresentation = .expanded
            captureGroup = g
            return g
        case Self.zoom:
            let labels = ["Zoom Out", "Zoom to Fit", "Zoom To Actual Size", "Zoom In"]
            let images = ["minus.magnifyingglass", "arrow.up.left.and.down.right.magnifyingglass", "1.magnifyingglass", "plus.magnifyingglass"]
                .enumerated().compactMap { image($0.element, labels[$0.offset]) }
            let g = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .selectOne, labels: labels,
                                       target: self, action: #selector(zoomChosen(_:)))
            for (sub, l) in zip(g.subitems, labels) { sub.toolTip = l }
            g.controlRepresentation = .expanded
            zoomGroup = g
            updateZoom()
            return g
        case Self.open:
            let i = NSToolbarItem(itemIdentifier: id)
            i.image = image("arrow.down.right.and.arrow.up.left", "Open in New Window")
            i.label = "Open in New Window"
            i.toolTip = "Switch to compact window"
            i.isBordered = true
            i.target = self
            i.action = #selector(openClicked(_:))
            return i
        case Self.headset:
            let i = NSToolbarItem(itemIdentifier: id)
            i.image = image("eyeglasses", "View in Headset")
            i.label = "View in Headset"
            i.toolTip = "View in Headset (⌃⌘H)"
            i.isBordered = true
            i.target = self
            i.action = #selector(headsetClicked(_:))
            return i
        case Self.more:
            let i = NSMenuToolbarItem(itemIdentifier: id)
            i.image = image("ellipsis", "More Actions")
            i.label = "More Actions"
            i.toolTip = "More Actions"
            i.showsIndicator = false
            i.menu = moreMenu
            return i
        case Self.tabs:
            let labels = ["Settings", "Reports", "Info"]
            let images = Self.tabSymbols.enumerated().compactMap { image($0.element, labels[$0.offset]) }
            let g = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .selectOne, labels: labels,
                                       target: self, action: #selector(tabChosen(_:)))
            for (sub, l) in zip(g.subitems, labels) { sub.toolTip = l }
            g.controlRepresentation = .expanded
            tabGroup = g
            updateTabs()
            return g
        default:
            return nil
        }
    }

    func update() {
        updateZoom()
        updateTabs()
        updateFilterLook()
        updateCapture(owner.canvas.capturesKeyboard)
        updateSidebarItems()
        owner.view.window?.toolbar?.validateVisibleItems()
    }

    func updateZoom() {
        guard let g = zoomGroup else { return }
        switch owner.canvas.zoom {
        case .fit: g.selectedIndex = 1
        case .actual: g.selectedIndex = 2
        case .scale: break
        }
    }

    func updateTabs() { tabGroup?.selectedIndex = owner.inspectorTab.rawValue }

    func updateCapture(_ on: Bool) {
        guard let g = captureGroup else { return }
        g.setSelected(on, at: 0)
        g.setSelected(false, at: 1)
    }

    func updateSidebarItems() {
        guard #available(macOS 15.0, *), let t = owner.view.window?.toolbar else { return }
        for i in t.items {
            switch i.itemIdentifier {
            case Self.add, Self.filter: i.isHidden = !owner.sidebarShown
            case Self.captureGroup:
                if let g = i as? NSToolbarItemGroup, g.subitems.count == 2 { g.subitems[1].isHidden = owner.selected == nil }
            default: break
            }
        }
    }

    func updateFilterLook() {
        let filtered = owner.sidebarModel.filter != .all
        filterItem?.image = NSImage(systemSymbolName: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease",
                                    accessibilityDescription: "Filter")
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.captureGroup:
            if let g = item as? NSToolbarItemGroup, g.subitems.count == 2 { g.subitems[1].isEnabled = false }
            return owner.selected != nil
        case Self.zoom, Self.more: return owner.selected != nil
        case Self.open: return owner.selected?.state == "Booted" && owner.selected?.isSwiftCodeRemote == true
        case Self.headset:
            let title = owner.headsetCommandTitle(for: owner.selected)
            item.label = title
            item.toolTip = title + " (⌃⌘H)"
            item.image = NSImage(systemSymbolName: title == "View in Headset" ? "eyeglasses" : "macwindow", accessibilityDescription: title)
            if #available(macOS 15.0, *) { item.isHidden = !owner.headsetControlsShown }
            return owner.canToggleHeadset(owner.selected)
        default: return true
        }
    }

    @objc func captureGroupChosen(_ sender: NSToolbarItemGroup) {
        owner.canvas.setCapturesKeyboard(sender.isSelected(at: 0))
        updateCapture(owner.canvas.capturesKeyboard)
    }

    @objc func zoomChosen(_ sender: NSToolbarItemGroup) {
        let commands: [DeviceCommand] = [.zoomOut, .zoomToFit, .physicalSize, .zoomIn]
        guard commands.indices.contains(sender.selectedIndex) else { return }
        owner.canvas.perform(commands[sender.selectedIndex])
    }

    @objc func openClicked(_ sender: Any?) { owner.openInNewWindow() }
    @objc func headsetClicked(_ sender: Any?) { owner.toggleHeadset() }

    @objc func tabChosen(_ sender: NSToolbarItemGroup) {
        owner.selectInspectorTab(DevicesController.InspectorTab(rawValue: sender.selectedIndex) ?? .settings)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === addMenu {
            for i in Self.addItems(target: self, hub: owner) { menu.addItem(i) }
        } else if menu === filterMenu {
            for i in filterItems() { menu.addItem(i) }
        } else if menu === moreMenu {
            for i in moreItems() { menu.addItem(i) }
        }
    }

    static func addItems(target: AnyObject?, hub: DevicesController? = nil) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        let watches = hub?.canCreateWatches ?? false
        let visions = hub?.canCreateVisionDevices ?? false
        for (title, on) in [("iPhone…", true), ("iPad…", true), ("Apple Watch…", watches), ("Apple Vision Pro…", visions), ("Apple TV…", false)] {
            let watch = title == "Apple Watch…", vision = title == "Apple Vision Pro…"
            let action = watch ? #selector(DevicesController.newWatchChosen(_:))
                : vision ? #selector(DevicesController.newVisionDeviceChosen(_:)) : #selector(addSimulator(_:))
            let i = NSMenuItem(title: title, action: on ? action : nil, keyEquivalent: "")
            i.target = watch || vision ? hub : target
            i.isEnabled = on
            out.append(i)
            if watch {
                let p = NSMenuItem(title: "iPhone with Paired Watch…", action: on ? #selector(DevicesController.newPairedPhoneChosen(_:)) : nil, keyEquivalent: "")
                p.target = hub
                p.isEnabled = on
                out.append(p)
            }
        }
        out.append(.separator())
        let pair = NSMenuItem(title: "Pair Nearby Device…", action: nil, keyEquivalent: "")
        pair.isEnabled = false
        out.append(pair)
        return out
    }

    @objc func addSimulator(_ sender: Any?) { SettingsWindowController.shared.show(pane: "Simulators") }

    func filterItems() -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        for f in HubFilter.allCases {
            let i = NSMenuItem(title: f.rawValue, action: #selector(filterChosen(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = f.rawValue
            i.state = owner.sidebarModel.filter == f ? .on : .off
            out.append(i)
        }
        out.append(.separator())
        let sort = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        let sm = NSMenu(title: "Sort By")
        for s in HubSort.allCases {
            let i = NSMenuItem(title: s.rawValue, action: #selector(sortChosen(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = s.rawValue
            i.state = owner.sortChosen && owner.sidebarModel.sort == s ? .on : .off
            sm.addItem(i)
        }
        sort.submenu = sm
        out.append(sort)
        return out
    }

    @objc func filterChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let f = HubFilter(rawValue: raw) else { return }
        owner.setFilter(f)
        updateFilterLook()
    }

    @objc func sortChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let s = HubSort(rawValue: raw) else { return }
        owner.setSort(owner.sortChosen && owner.sidebarModel.sort == s ? nil : s)
    }

    func moreItems() -> [NSMenuItem] {
        guard let r = owner.selected else { return [] }
        var out = owner.lifecycleItems(for: r) + owner.headsetMenuItems(for: r)
        let bezels = NSMenuItem(title: owner.canvas.showsBezels ? "Hide Bezels" : "Show Bezels", action: #selector(toggleBezels(_:)), keyEquivalent: "")
        bezels.target = self
        let stats = NSMenuItem(title: "Show Frame Rate", action: #selector(toggleStatistics(_:)), keyEquivalent: "")
        stats.target = self
        stats.state = owner.canvas.showsStatistics ? .on : .off
        out += [bezels, stats]
        if r.isSwiftCodeRemote, let i = owner.rows.firstIndex(where: { $0.identifier == r.identifier }) {
            out.append(.separator())
            let erase = NSMenuItem(title: DevicesController.eraseTitle, action: #selector(DevicesController.eraseChosen(_:)), keyEquivalent: "")
            erase.target = owner
            erase.tag = i
            out.append(erase)
        }
        return out
    }

    @objc func toggleBezels(_ sender: Any?) {
        owner.canvas.showsBezels.toggle()
        owner.defaults.set(owner.canvas.showsBezels, forKey: DevicesController.bezelsKey)
    }

    @objc func toggleStatistics(_ sender: Any?) { owner.canvas.showsStatistics.toggle() }
}
