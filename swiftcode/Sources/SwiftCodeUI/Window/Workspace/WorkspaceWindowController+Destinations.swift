import AppKit
import SwiftCodeBuild
import SwiftCodeIDECore

extension WorkspaceWindowController {
    public func destinationMenuModel(filter: String = "") -> DestinationMenuModel {
        let all = session.model.destinationGroups.flatMap(\.destinations)
        let proj = session.model.projects.keys.sorted().first.flatMap { session.model.projects[$0] }
        var (platforms, ipad) = proj.map(DestinationMenuModel.platforms(of:)) ?? ([], false)
        if let s = schemeTargetPlatform { platforms = s.platforms; ipad = ipad && s.platforms.contains("iOS") }
        let product = productPlatform
        var targets: [String: String] = [:]
        if let p = product.platform, let t = product.deploymentTarget { targets[p] = t }
        return DestinationMenuModel(current: session.destination,
                                    devices: all.filter { $0.kind == .device },
                                    simulators: all.filter { $0.kind == .simulator || $0.isSwiftCodeRemoteSimulator },
                                    platforms: platforms, designedForIPad: ipad, deploymentTargets: targets, filter: filter)
    }

    func rebuildDestinationMenu(filter: String = "", expandIncompatible: Bool = false) {
        let menu = destinationPopUp.menu!
        let filterItem: NSMenuItem
        if let existing = menu.items.first, existing.view is NSSearchField {
            filterItem = existing
        } else {
            let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            field.placeholderString = "Filter"
            field.target = self
            field.action = #selector(destinationFilterChanged(_:))
            field.sendsSearchStringImmediately = true
            filterItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            filterItem.view = field
        }
        menu.removeAllItems()
        menu.addItem(filterItem)
        let model = destinationMenuModel(filter: filter)
        func row(_ d: Destination) -> NSMenuItem {
            let item = DestinationMenuItem(title: d.name, action: nil, keyEquivalent: "")
            item.representedObject = Self.menuKey(for: d)
            item.image = NSImage(systemSymbolName: Self.symbol(for: d), accessibilityDescription: nil)
            item.osVersion = d.osVersion
            item.name = d.name
            if d.isSwiftCodeRemoteSimulator {
                item.subtitle = ExperimentalNotice.label
                item.toolTip = ExperimentalNotice.simulator
            }
            return item
        }
        var recent: Int?
        for s in model.sections {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: s.title))
            for d in s.destinations {
                let item = row(d)
                if s.title == "Recent" { item.state = .on; recent = recent ?? menu.items.count }
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        if expandIncompatible && !model.incompatible.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: DestinationMenuModel.incompatibleTitle))
            for d in model.incompatible { let i = row(d); i.representedObject = nil; i.isEnabled = false; menu.addItem(i) }
            menu.addItem(.separator())
        } else {
            let inc = NSMenuItem(title: DestinationMenuModel.incompatibleTitle, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for d in model.incompatible { let i = row(d); i.isEnabled = false; sub.addItem(i) }
            sub.autoenablesItems = false
            inc.submenu = sub
            inc.isEnabled = !model.incompatible.isEmpty
            menu.addItem(inc)
        }
        menu.addItem(NSMenuItem(title: DestinationMenuModel.manageDevicesTitle, action: #selector(manageDevicesChosen(_:)), keyEquivalent: ""))
        menu.items.last?.target = self
        if filter.isEmpty {
            menu.addItem(NSMenuItem(title: Self.getRuntimeTitle, action: #selector(getRuntimeChosen(_:)), keyEquivalent: ""))
            menu.items.last?.target = self
        }
        if !model.sections.contains(where: { $0.destinations.contains(where: \.isSwiftCodeRemoteSimulator) }) && filter.isEmpty {
            let setUp = NSMenuItem(title: Self.setUpSimulatorTitle, action: #selector(setUpSimulatorChosen(_:)), keyEquivalent: "")
            setUp.target = self
            setUp.subtitle = ExperimentalNotice.label
            setUp.toolTip = ExperimentalNotice.simulator
            menu.addItem(setUp)
        }
        let current = session.destination.map(Self.menuKey(for:))
        if let i = recent ?? menu.items.firstIndex(where: { ($0.representedObject as? String) == current })
            ?? menu.items.firstIndex(where: { $0.representedObject is String }) {
            destinationPopUp.selectItem(at: i)
        }
        for item in menu.items { item.submenu?.items.forEach { ($0 as? DestinationMenuItem)?.showsVersion = true } }
        destinationPopUp.invalidateIntrinsicContentSize()
        scheduleToolbarFit()
    }

    public var productPlatform: (platform: String?, deploymentTarget: String?) {
        if let s = schemeTargetPlatform { return (s.platform, s.deploymentTarget) }
        let proj = session.model.projects.keys.sorted().first.flatMap { session.model.projects[$0] }
        return proj.map(DestinationMenuModel.productPlatform(of:)) ?? (nil, nil)
    }

    var schemeTargetPlatform: (platforms: Set<String>, platform: String?, deploymentTarget: String?)? {
        guard let scheme = session.scheme, let key = session.model.projects.keys.sorted().first, let proj = session.model.projects[key] else { return nil }
        let name = WatchCompanion.targetName(scheme: scheme, schemes: session.model.loadSchemes())
        guard name != proj.targets.first?.string("name") else { return nil }
        let platforms = WatchCompanion.platforms(ofTarget: name, in: proj)
        guard !platforms.isEmpty, platforms != DestinationMenuModel.platforms(of: proj).platforms else { return nil }
        let platform = ["watchOS", "iOS", "tvOS", "visionOS", "macOS"].first(where: platforms.contains)
        return (platforms, platform, platform.flatMap { WatchCompanion.deploymentTarget(ofTarget: name, platform: $0, in: proj) })
    }

    public var defaultDestinationTraits: (supportsMacOS: Bool, deviceFamilies: Set<String>?) {
        let proj = session.model.projects.keys.sorted().first.flatMap { session.model.projects[$0] }
        return proj.map(DestinationMenuModel.defaultDestinationTraits(of:)) ?? (false, nil)
    }

    func chooseDefaultDestination() {
        let scheme = session.scheme ?? ""
        let (platform, target) = productPlatform
        let anySim = platform.map(DestinationCatalog.anySimulator)
        let known = session.model.destinations + [anySim, .anyMac].compactMap { $0 }
        if let key = userState.destinations[scheme], let d = Self.destination(forKey: key, in: known) {
            session.destination = d
            destinationDefault.applied = d
            return
        }
        let current = session.destination
        let isDefault = current == nil || current == destinationDefault.applied
            || (destinationDefault.applied == nil && current == session.model.destinations.first)
        guard isDefault else { return }
        let sims = session.model.destinations.filter { $0.kind == .simulator || $0.isSwiftCodeRemoteSimulator }
        let traits = defaultDestinationTraits
        let d = DestinationCatalog.defaultDestination(platform: platform, deploymentTarget: target, simulators: sims,
                                                      supportsMacOS: traits.supportsMacOS, deviceFamilies: traits.deviceFamilies,
                                                      order: DestinationMenuModel.orderedSimulators)
        session.destination = d
        destinationDefault.applied = d
    }

    func rememberDestination() {
        guard let d = session.destination else { return }
        destinationDefault.applied = nil
        let scheme = session.scheme ?? ""
        updateUserState { $0.destinations[scheme] = Self.menuKey(for: d) }
    }

    public static func menuKey(for d: Destination) -> String { d.identifier ?? d.specifier }

    public static func destination(forKey key: String, in list: [Destination]) -> Destination? {
        list.first { $0.identifier == key } ?? list.first { $0.identifier == nil && $0.specifier == key }
    }

    public var destinationTitle: String {
        destinationPopUp.titleOfSelectedItem ?? ""
    }

    @objc func destinationFilterChanged(_ f: NSSearchField) { rebuildDestinationMenu(filter: f.stringValue) }
    @objc func manageDevicesChosen(_ sender: Any?) { _ = showDevices(sender) }
    static let setUpSimulatorTitle = "Set Up SwiftCode Simulator…"
    static let getRuntimeTitle = "Get a Simulator Runtime…"
    @objc func getRuntimeChosen(_ sender: Any?) { RuntimeSetupWindowController.show() }
    @objc func setUpSimulatorChosen(_ sender: Any?) { SettingsWindowController.shared.show(pane: "Simulators") }

    @discardableResult
    public func refreshRemoteRuntimeVersion(defaults: UserDefaults = Preferences.shared.defaults, ssh: String? = nil) -> Task<Void, Never>? {
        var settings = RemoteSimulatorSettings.load(defaults)
        if let ssh { settings.ssh = ssh }
        let roots = settings.allRuntimeRoots.filter { !RemoteSimulatorSettings.hasRuntimeVersion(for: $0, defaults) }
        guard settings.isConfigured, !roots.isEmpty else { return nil }
        let primary = settings.runtimeRoot
        let probes = roots.map { root in
            RemoteSimulator(settings: settings, target: RemoteSimulatorTarget(runtimeRoot: root, runtimeVersion: nil, deviceType: .simdDefault,
                                                                              deviceDirectoryName: settings.deviceName, isPrimary: false))
        }
        return Task { [weak self] in
            var found = false
            for remote in probes {
                guard let v = await Task.detached(operation: { remote.readRuntimeSystemVersion() }).value else { continue }
                RemoteSimulatorSettings.saveRuntimeVersion(v.version, root: remote.runtimeRoot, defaults, primary: remote.runtimeRoot == primary)
                RemoteSimulatorSettings.saveRuntimePlatform(v.platform, root: remote.runtimeRoot, defaults)
                found = true
            }
            guard found, let self else { return }
            self.setDestinationGroups(self.session.model.destinationGroups)
        }
    }
}

final class DestinationMenuItem: NSMenuItem {
    var osVersion: String?
    var showsVersion = false {
        didSet {
            guard showsVersion != oldValue else { return }
            let name = self.name
            guard showsVersion, let v = osVersion else { attributedTitle = nil; title = name; return }
            let text = NSMutableAttributedString(string: name + "\t" + v)
            let para = NSMutableParagraphStyle()
            para.tabStops = [NSTextTab(textAlignment: .right, location: 300)]
            text.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: text.length))
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                              range: NSRange(location: name.utf16.count + 1, length: v.utf16.count))
            attributedTitle = text
        }
    }
    lazy var name: String = title
}

final class DestinationPopUpButton: NSPopUpButton, NSMenuDelegate {
    override init(frame: NSRect, pullsDown flag: Bool) {
        super.init(frame: frame, pullsDown: flag)
        menu?.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var menu: NSMenu? {
        didSet { menu?.delegate = self }
    }

    override var intrinsicContentSize: NSSize {
        let probe = NSPopUpButton(frame: .zero, pullsDown: false)
        probe.isBordered = isBordered
        probe.controlSize = controlSize
        probe.font = font
        probe.imagePosition = imagePosition
        if let arrow = (cell as? NSPopUpButtonCell)?.arrowPosition { (probe.cell as? NSPopUpButtonCell)?.arrowPosition = arrow }
        let item = NSMenuItem(title: selectedItem?.title ?? "", action: nil, keyEquivalent: "")
        item.image = selectedItem?.image
        probe.menu?.addItem(item)
        probe.select(item)
        return NSSize(width: ceil(probe.intrinsicContentSize.width), height: super.intrinsicContentSize.height)
    }

    override func select(_ item: NSMenuItem?) {
        super.select(item)
        invalidateIntrinsicContentSize()
    }

    override func selectItem(at index: Int) {
        super.selectItem(at: index)
        invalidateIntrinsicContentSize()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { versions(true, in: menu) }
    func menuDidClose(_ menu: NSMenu) {
        versions(false, in: menu)
        invalidateIntrinsicContentSize()
    }

    private func versions(_ on: Bool, in menu: NSMenu) {
        guard menu === self.menu else { return }
        for item in menu.items { (item as? DestinationMenuItem)?.showsVersion = on }
    }
}
