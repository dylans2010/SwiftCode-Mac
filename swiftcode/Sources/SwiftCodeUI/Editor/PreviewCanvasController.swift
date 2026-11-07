import AppKit
import SwiftCodeDeviceUI
import SwiftCodeIDECore

@MainActor
public final class PreviewCanvasController: NSViewController {
    public enum State: Equatable {
        case empty(String)
        case building
        case rendered([PreviewRenderer.Rendered])
        case failed(String)
        case live([PreviewLiveTile])
        case needsSimulator(String)
    }

    public enum Layout: Int { case grid, single }

    public private(set) var state: State = .empty("No Previews")
    public private(set) var selectedIndex = 0
    public private(set) var layout: Layout = .single
    public private(set) var colorScheme: PreviewRenderer.ColorScheme = .light
    public private(set) var isPaused = true
    public private(set) var mode: PreviewCanvasMode = .live
    public private(set) var showsVariants = false
    public private(set) var zoom: CGFloat?
    public static let zoomSteps: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2]
    public var onRefresh: (() -> Void)?
    public var onLayoutChange: (() -> Void)?
    public var onIssue: ((PreviewIssue) -> Void)?
    public var onRevealPreview: ((Int) -> Void)?
    public var onOpenSimulatorSettings: (() -> Void)? = { SettingsWindowController.shared.show(pane: "Simulators") }
    public internal(set) var simulatorSettingsButton: NSButton?
    public var onPin: (() -> Void)?
    public private(set) var liveSession: DeviceLiveSession?
    public var liveScreen = CGSize(width: 402, height: 874)
    public private(set) var isUpdating = false
    public private(set) var banner: (title: String, issues: [PreviewIssue], message: String?)?
    public private(set) var variantKind: PreviewVariantKind?
    public var pinnedTitle: String? { didSet { if isViewLoaded { show() } } }
    public internal(set) var liveTileViews: [NSView] = []
    var bannerView: PreviewBannerView?
    let pinButton = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin") ?? NSImage(), target: nil, action: nil)
    let tabStrip = NSStackView()
    let modeButtons: [NSButton] = PreviewCanvasMode.allCases.map { m in
        let b = NSButton(image: NSImage(systemSymbolName: m.symbol, accessibilityDescription: m.title) ?? NSImage(), target: nil, action: nil)
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .texturedRounded
        b.isBordered = false
        b.toolTip = m.title
        b.tag = m.rawValue
        return b
    }
    let zoomPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let fitButton = NSButton(image: NSImage(systemSymbolName: "camera", accessibilityDescription: "Capture") ?? NSImage(), target: nil, action: nil)
    let deviceButton = NSButton(image: NSImage(systemSymbolName: "rectangle.portrait", accessibilityDescription: "Device") ?? NSImage(), target: nil, action: nil)
    public var devices = PreviewDeviceMenuModel() { didSet { if isViewLoaded { updateDevicePopUp() } } }
    let devicePopUp = NSPopUpButton(frame: .zero, pullsDown: true)
    public private(set) var settings = PreviewCanvasSettings()
    let settingsButton = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Canvas Settings") ?? NSImage(), target: nil, action: nil)
    lazy var pausedCapsule = PreviewPausedCapsule(target: self, action: #selector(resumeClicked))
    let statusLabel = NSTextField(labelWithString: "")
    let body = NSView()
    public private(set) var names: [String] = []
    public var tabTitles: [String] = [] { didSet { if isViewLoaded { show() } } }
    public internal(set) var cardTitles: [String] = []
    public private(set) var headerTabs: [(title: String, badge: String)] = []

    public override func loadView() {
        let root = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))
        tabStrip.spacing = 2
        tabStrip.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(pinClicked)
        pinButton.toolTip = "Pin Preview"
        let header = NSStackView(views: [pinButton, tabStrip, NSView(), statusLabel])
        header.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        for b in modeButtons { b.target = self; b.action = #selector(modeClicked(_:)) }
        zoomPopUp.controlSize = .small
        zoomPopUp.font = .systemFont(ofSize: 11)
        zoomPopUp.isBordered = false
        zoomPopUp.target = self
        zoomPopUp.action = #selector(zoomChosen)
        for (b, sel, tip) in [(fitButton, #selector(capture(_:)), "Capture"), (deviceButton, #selector(deviceSettings(_:)), "Device"),
                              (settingsButton, #selector(canvasSettings(_:)), "Canvas Settings")] {
            b.isBordered = false
            b.target = self
            b.action = sel
            b.toolTip = tip
        }
        devicePopUp.isBordered = false
        devicePopUp.controlSize = .small
        devicePopUp.font = .systemFont(ofSize: 11)
        devicePopUp.setAccessibilityLabel("Preview Device")
        updateDevicePopUp()
        let left = NSStackView(views: [devicePopUp] + modeButtons)
        left.spacing = 4
        let right = NSStackView(views: [fitButton, deviceButton, settingsButton])
        right.spacing = 6
        let bar = NSView()
        for v in [left, zoomPopUp, right] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(v) }
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8), left.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            zoomPopUp.centerXAnchor.constraint(equalTo: bar.centerXAnchor), zoomPopUp.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8), right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        let sep = NSBox(), sep2 = NSBox()
        sep.boxType = .separator
        sep2.boxType = .separator
        for v in [header, sep, body, sep2, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 28),
            sep.topAnchor.constraint(equalTo: header.bottomAnchor), sep.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            body.topAnchor.constraint(equalTo: sep.bottomAnchor), body.bottomAnchor.constraint(equalTo: sep2.topAnchor),
            body.leadingAnchor.constraint(equalTo: root.leadingAnchor), body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sep2.leadingAnchor.constraint(equalTo: root.leadingAnchor), sep2.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sep2.bottomAnchor.constraint(equalTo: bar.topAnchor),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor), bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor), bar.heightAnchor.constraint(equalToConstant: 28),
        ])
        view = root
        show()
    }

    private var lastBodySize = CGSize.zero

    public override func viewDidLayout() {
        super.viewDidLayout()
        guard case .live = state, zoom == nil else { return }
        let size = body.bounds.size
        if abs(size.width - lastBodySize.width) > 8 || abs(size.height - lastBodySize.height) > 8 {
            lastBodySize = size
            show()
        }
    }

    public func setNames(_ list: [String]) {
        names = list
        if tabTitles.count != list.count { tabTitles = list }
        if selectedIndex >= list.count { selectedIndex = 0 }
        if isViewLoaded { show() }
    }

    public func setState(_ s: State) {
        state = s
        if case .live = s {} else { isUpdating = false }
        if case .rendered = s {
            names = shown.map(\.name)
            if tabTitles.count != names.count { tabTitles = names }
            if selectedIndex >= names.count { selectedIndex = 0 }
        }
        if isViewLoaded { show() }
    }

    public func resume() {
        guard isPaused else { return }
        isPaused = false
        if isViewLoaded { show() }
        onRefresh?()
    }

    public func select(_ i: Int, zoom: Bool = false) {
        selectedIndex = i
        if zoom { layout = .single }
        if isViewLoaded { show() }
    }

    public func setLayout(_ l: Layout) {
        layout = l
        if isViewLoaded { show() }
    }

    public func setColorScheme(_ s: PreviewRenderer.ColorScheme) {
        colorScheme = s
        if isViewLoaded { show() }
    }

    public func setMode(_ m: PreviewCanvasMode) {
        switch m {
        case .live, .selectable: mode = m
        case .variants:
            if isLiveCanvas {
                let all = PreviewVariantKind.allCases
                let next = variantKind.flatMap { all.firstIndex(of: $0) }.map { $0 + 1 < all.count ? all[$0 + 1] : nil } ?? all.first
                setVariants(next)
                return
            }
            showsVariants.toggle()
        case .grid:
            layout = layout == .grid ? .single : .grid
            if isLiveCanvas { onLayoutChange?() }
        }
        if isViewLoaded { show() }
    }

    public func setVariants(_ kind: PreviewVariantKind?) {
        variantKind = kind
        showsVariants = kind != nil
        if kind != nil { layout = .single }
        if isViewLoaded { show() }
        onLayoutChange?()
    }

    public var isLiveCanvas: Bool { liveSession != nil }

    public func attach(_ session: DeviceLiveSession?) {
        if liveSession === session { return }
        liveSession?.removeObserver(self)
        liveSession = session
        session?.addObserver(self)
        if isViewLoaded { show() }
    }

    public func setUpdating(_ on: Bool) {
        isUpdating = on
        if isViewLoaded { reloadTabs(); statusLabel.stringValue = on ? "Updating…" : statusLabel.stringValue == "Updating…" ? "" : statusLabel.stringValue }
    }

    public func setBanner(title: String, issues: [PreviewIssue] = [], message: String? = nil) {
        banner = (title, issues, message)
        if isViewLoaded { show() }
    }

    public func clearBanner() {
        guard banner != nil else { return }
        banner = nil
        if isViewLoaded { show() }
    }

    @objc private func pinClicked() { onPin?() }

    public func setZoom(_ z: CGFloat?) {
        zoom = z
        if isViewLoaded { show() }
    }

    public var zoomTitle: String { zoom.map { "\(Int(($0 * 100).rounded()))%" } ?? "Fit" }

    public var shown: [PreviewRenderer.Rendered] {
        guard case .rendered(let all) = state else { return [] }
        let match = all.filter { $0.scheme == colorScheme }
        return match.isEmpty ? all.filter { $0.scheme == .light } : match
    }

    @objc private func resumeClicked() { resume() }
    @objc private func modeClicked(_ b: NSButton) { setMode(PreviewCanvasMode(rawValue: b.tag) ?? .live) }
    @objc private func tabClicked(_ g: NSClickGestureRecognizer) {
        guard let v = g.view as? PreviewTabView else { return }
        select(v.index, zoom: true)
        if isLiveCanvas { onLayoutChange?() }
    }
    @objc private func refreshClicked() { onRefresh?() }
    @objc private func cardClicked(_ g: NSClickGestureRecognizer) { if let v = g.view as? PreviewCard { select(v.index, zoom: true) } }

    func tileClicked(_ preview: Int) {
        if selectedIndex != preview {
            selectedIndex = preview
            reloadTabs()
            for v in liveTileViews { (v as? PreviewLiveTileView).map { $0.isSelected = $0.tile.preview == preview && layout == .grid } }
        }
        if mode == .selectable { onRevealPreview?(preview) }
    }
    @objc private func zoomChosen() {
        let i = zoomPopUp.indexOfSelectedItem
        setZoom(i <= 0 ? nil : Self.zoomSteps[i - 1])
    }
    @objc public func zoomToFit(_ sender: Any?) { setZoom(nil) }

    func deviceMenu() -> NSMenu {
        let m = NSMenu()
        for r in devices.rows {
            if r == "—" { m.addItem(.separator()); continue }
            if r.hasPrefix("#") { m.addItem(NSMenuItem.sectionHeader(title: String(r.dropFirst()))); continue }
            let i = NSMenuItem(title: r, action: #selector(deviceItem(_:)), keyEquivalent: "")
            i.target = self
            if let g = PreviewDeviceMenuModel.generics.first(where: { "\($0.title) \($0.detail)" == r }) {
                let t = NSMutableAttributedString(string: g.title + " ")
                t.append(NSAttributedString(string: g.detail, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                i.attributedTitle = t
            }
            if r == "More" { i.submenu = NSMenu(); i.action = nil }
            i.state = (devices.chosen == nil && r.hasPrefix("Automatic")) || devices.chosen == r ? .on : .off
            m.addItem(i)
        }
        return m
    }

    @objc private func deviceItem(_ i: NSMenuItem) { chooseDevice(i.title.hasPrefix("Automatic") ? nil : i.title) }
    public func chooseDevice(_ d: String?) {
        devices.chosen = d
        onLayoutChange?()
    }

    public var devicePopUpTitle: String { devicePopUp.itemArray.first?.title ?? "" }

    func updateDevicePopUp() {
        let menu = deviceMenu()
        menu.insertItem(NSMenuItem(title: devices.chosen ?? devices.rows.first ?? "", action: nil, keyEquivalent: ""), at: 0)
        devicePopUp.menu = menu
    }

    public func setSetting(_ name: String, _ on: Bool) {
        if on { settings.on.insert(name) } else { settings.on.remove(name) }
        if name == "Color Scheme" { setColorScheme(on ? .dark : .light) } else if isViewLoaded { show() }
        if ["Color Scheme", "Orientation", "Dynamic Type"].contains(name) { onLayoutChange?() }
    }

    func settingsView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        for n in PreviewCanvasSettings.names {
            let sw = NSSwitch()
            sw.controlSize = .mini
            sw.state = settings.on.contains(n) ? .on : .off
            sw.identifier = .init(n)
            sw.target = self
            sw.action = #selector(switchFlipped(_:))
            stack.addArrangedSubview(NSStackView(views: [sw, NSTextField(labelWithString: n)]))
        }
        return stack
    }

    @objc private func switchFlipped(_ s: NSSwitch) { if let n = s.identifier?.rawValue { setSetting(n, s.state == .on) } }

    public var baseVariant: PreviewVariant {
        PreviewVariant(colorScheme: settings.on.contains("Color Scheme") ? "dark" : nil,
                       dynamicType: settings.on.contains("Dynamic Type") ? dynamicTypeSize : nil,
                       orientation: settings.on.contains("Orientation") ? .landscapeLeft : nil)
    }

    public var dynamicTypeSize = "accessibility1"

    @discardableResult
    @objc public func capture(_ sender: Any?) -> Bool {
        if case .live(let tiles) = state, let image = liveSession?.image, !tiles.isEmpty {
            let t = tiles.first { $0.preview == selectedIndex } ?? tiles[0]
            let rect = PreviewCanvasLayout.pixelRect(t.region, screen: liveScreen, imageSize: CGSize(width: image.width, height: image.height))
            guard let crop = image.cropping(to: rect) else { return false }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([NSImage(cgImage: crop, size: t.size)])
        }
        let list = shown
        guard !list.isEmpty, let img = NSImage(contentsOf: list[min(selectedIndex, list.count - 1)].png) else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([img])
    }

    @objc func deviceSettings(_ sender: NSButton) { deviceMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender) }
    @objc func canvasSettings(_ sender: NSButton) {
        let pop = NSPopover()
        pop.behavior = .transient
        let vc = NSViewController()
        vc.view = settingsView()
        pop.contentViewController = vc
        pop.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    public var statusText: String { statusLabel.stringValue }

    func show() {
        for b in modeButtons {
            let m = PreviewCanvasMode(rawValue: b.tag)!
            let on = m == mode || (m == .variants && showsVariants) || (m == .grid && layout == .grid)
            b.state = on ? .on : .off
            b.contentTintColor = on ? .controlAccentColor : .secondaryLabelColor
        }
        zoomPopUp.removeAllItems()
        zoomPopUp.addItems(withTitles: ["Fit"] + Self.zoomSteps.map { "\(Int($0 * 100))%" })
        zoomPopUp.selectItem(withTitle: zoomTitle)
        reloadTabs()
        body.subviews.forEach { $0.removeFromSuperview() }
        liveTileViews = []
        bannerView = nil
        simulatorSettingsButton = nil
        cardTitles = []
        framedCount = 0
        let content: NSView
        if isPaused && !names.isEmpty {
            statusLabel.stringValue = ""
            content = topCentered(pausedCapsule)
        } else { switch state {
        case .empty(let message):
            statusLabel.stringValue = message
            content = centered(NSTextField(labelWithString: message))
        case .building:
            statusLabel.stringValue = "Building…"
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.startAnimation(nil)
            content = centered(spinner)
        case .failed(let message):
            statusLabel.stringValue = "Build failed"
            content = errorCard(message)
        case .needsSimulator(let message):
            statusLabel.stringValue = "Needs a simulator"
            content = needsSimulatorCard(message)
        case .live(let tiles):
            statusLabel.stringValue = isUpdating ? "Updating…" : ""
            content = liveContent(tiles)
        case .rendered:
            let list = shown
            if list.isEmpty {
                statusLabel.stringValue = "No Previews"
                content = centered(NSTextField(labelWithString: "No Previews"))
            } else if layout == .grid {
                statusLabel.stringValue = "\(list.count) preview\(list.count == 1 ? "" : "s")"
                content = grid(list)
            } else {
                let i = min(selectedIndex, list.count - 1)
                statusLabel.stringValue = ""
                if showsVariants, case .rendered(let all) = state {
                    let both = all.filter { $0.name == list[i].name }
                    let row = NSStackView(views: both.map { framed($0) })
                    row.spacing = 16
                    content = centered(row)
                } else {
                    content = centered(framed(list[i]))
                }
            }
        } }
        content.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: body.topAnchor), content.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor), content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
    }

    public internal(set) var framedCount = 0

    private func framed(_ r: PreviewRenderer.Rendered) -> NSView {
        let image = NSImage(contentsOf: r.png) ?? NSImage()
        if let z = zoom { image.size = NSSize(width: image.size.width * z, height: image.size.height * z) }
        let iv = NSImageView(image: image)
        iv.imageScaling = .scaleProportionallyDown
        iv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iv.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        framedCount += 1
        cardTitles.append(r.name)
        return PreviewDeviceFrameView(content: iv)
    }

    func reloadTabs() {
        tabStrip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        headerTabs = []
        guard !isPaused else { return }
        let titles = tabTitles.count == names.count ? tabTitles : names
        let badge: PreviewTabView.Badge
        switch state {
        case .building: badge = .spinner
        case .rendered: badge = .eye
        case .live: badge = isUpdating ? .spinner : .eye
        default: badge = .none
        }
        pinButton.contentTintColor = pinnedTitle != nil ? .controlAccentColor : .secondaryLabelColor
        pinButton.image = NSImage(systemSymbolName: pinnedTitle != nil ? "pin.fill" : "pin", accessibilityDescription: "Pin") ?? NSImage()
        for (i, t) in titles.enumerated() {
            let tab = PreviewTabView(title: t)
            tab.index = i
            tab.badge = badge
            tab.isSelected = i == selectedIndex && layout == .single
            tab.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tabClicked(_:))))
            tabStrip.addArrangedSubview(tab)
            headerTabs.append((t, badge == .spinner ? "spinner" : badge == .eye ? "eye" : ""))
        }
    }

    private func card(_ r: PreviewRenderer.Rendered, index: Int, large: Bool) -> NSView {
        let image = NSImage(contentsOf: r.png) ?? NSImage()
        if !large {
            let scale = min(1, 180 / max(image.size.width, image.size.height, 1))
            image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        }
        let iv = NSImageView(image: image)
        iv.imageScaling = .scaleProportionallyDown
        let name = NSTextField(labelWithString: r.name)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .secondaryLabelColor
        let stack = PreviewCard(views: [name, iv])
        stack.index = index
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.08).cgColor
        stack.layer?.borderWidth = index == selectedIndex && !large ? 2 : 1
        stack.layer?.borderColor = (index == selectedIndex && !large ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        let click = NSClickGestureRecognizer(target: self, action: #selector(cardClicked(_:)))
        stack.addGestureRecognizer(click)
        cardTitles.append(r.name)
        return stack
    }

    private func grid(_ list: [PreviewRenderer.Rendered]) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        rows.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        var i = 0
        while i < list.count {
            let row = NSStackView(views: list[i..<min(i + 2, list.count)].enumerated().map { card($0.element, index: i + $0.offset, large: false) })
            row.alignment = .top
            row.spacing = 12
            rows.addArrangedSubview(row)
            i += 2
        }
        let flipped = FlippedView()
        rows.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(rows)
        NSLayoutConstraint.activate([rows.topAnchor.constraint(equalTo: flipped.topAnchor), rows.leadingAnchor.constraint(equalTo: flipped.leadingAnchor),
                                     rows.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
                                     rows.trailingAnchor.constraint(lessThanOrEqualTo: flipped.trailingAnchor)])
        let scroll = NSScrollView()
        scroll.documentView = flipped
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }

    private func topCentered(_ v: NSView) -> NSView {
        let box = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: box.centerXAnchor), v.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            v.widthAnchor.constraint(lessThanOrEqualTo: box.widthAnchor, constant: -24),
        ])
        return box
    }

    private func centered(_ v: NSView) -> NSView {
        let box = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: box.centerXAnchor), v.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            v.widthAnchor.constraint(lessThanOrEqualTo: box.widthAnchor, constant: -24),
            v.heightAnchor.constraint(lessThanOrEqualTo: box.heightAnchor, constant: -24),
        ])
        return box
    }

    private func needsSimulatorCard(_ message: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.portrait", accessibilityDescription: "Simulator") ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: "Needs a Simulator")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: message)
        text.font = .systemFont(ofSize: 11)
        text.textColor = .secondaryLabelColor
        text.alignment = .center
        text.preferredMaxLayoutWidth = 300
        let button = NSButton(title: "Open Simulators Settings…", target: self, action: #selector(openSimulatorSettings))
        button.controlSize = .small
        simulatorSettingsButton = button
        let again = NSButton(title: "Check Again", target: self, action: #selector(refreshClicked))
        again.controlSize = .small
        let buttons = NSStackView(views: [again, button])
        buttons.spacing = 8
        let stack = NSStackView(views: [icon, title, text, buttons])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(12, after: text)
        return centered(stack)
    }

    @objc private func openSimulatorSettings() { onOpenSimulatorSettings?() }

    private func errorCard(_ message: String) -> NSView {
        let title = NSTextField(labelWithString: "Preview build failed")
        title.font = .boldSystemFont(ofSize: 12)
        let text = NSTextField(wrappingLabelWithString: message)
        text.font = Theme.font
        text.preferredMaxLayoutWidth = 320
        text.isSelectable = true
        let icon = NSImageView(image: NSImage(systemSymbolName: "xmark.octagon.fill", accessibilityDescription: "Error") ?? NSImage())
        icon.contentTintColor = Theme.errorColor
        let stack = NSStackView(views: [NSStackView(views: [icon, title]), text])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 8
        stack.layer?.borderWidth = 1
        stack.layer?.borderColor = Theme.errorColor.cgColor
        stack.layer?.backgroundColor = Theme.errorColor.withAlphaComponent(0.08).cgColor
        return centered(stack)
    }
}

final class PreviewCard: NSStackView {
    var index = 0
}

@MainActor final class CanvasAutoState {
    var modeOn = true
}

extension WorkspaceWindowController {
    public var isCanvasModeOn: Bool { canvasAuto.modeOn }

    public func setCanvasMode(_ on: Bool) {
        defer { updateToolbarState() }
        guard on else {
            canvasAuto.modeOn = false
            setCanvasShown(false)
            return
        }
        endEditorModes(except: .canvas)
        canvasAuto.modeOn = true
        updateCanvasForOpenedFile()
    }

    func updateCanvasForOpenedFile() {
        guard editor !== editorArea.tab.assistant else { return }
        let has = editor.fileURL.map { CanvasAutoShow.hasPreviews(fileName: $0.lastPathComponent, text: editor.text) } ?? false
        let other = editorArea.tab.assistant != nil || editor.isShowingComparison || editor.isShowingInlineComparison
        switch CanvasAutoShow.decide(hasPreviews: has, canvasShown: canvas != nil, canvasMode: canvasAuto.modeOn && !other) {
        case .show: setCanvasShown(true)
        case .hide: setCanvasShown(false)
        case .keep: if canvas != nil { refreshPreviews() }
        }
    }

    public var canvasShownAutomatically: Bool { canvas != nil && canvasAuto.modeOn }
}
