import AppKit
import SwiftCodeIDECore

@MainActor
public final class WelcomeWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let size = NSSize(width: 480, height: 632)
    public static let title = "Welcome to SwiftCode"
    public static let recentProjectsTitle = "Recent Projects"
    public static let buttonTitles = ["Open…", "Clone…", "New Project"]
    public static let buttonWidths: [CGFloat] = [107, 107, 130]
    public static let buttonHeight: CGFloat = 36
    public static let buttonSpacing: CGFloat = 8
    public static let buttonsTop: CGFloat = 242
    public static let closeButtonSize: CGFloat = 36
    public static let closeButtonInset: CGFloat = 20
    public static let recentsBoxFrame = NSRect(x: 60, y: 295, width: 360, height: 277)
    public static let nameCapHeight: CGFloat = 13
    public static let nameBaselineAboveButtons: CGFloat = 38
    public static let versionBaselineAboveButtons: CGFloat = 19
    public static let iconVisibleSide: CGFloat = 98
    public static let iconGapAboveName: CGFloat = 15.5
    static var iconMarginFraction: CGFloat { CGFloat(ProductIconGeometry.fieldMin / ProductIconGeometry.side) }
    public static var iconFrameSide: CGFloat {
        iconVisibleSide / CGFloat((ProductIconGeometry.fieldMax - ProductIconGeometry.fieldMin) / ProductIconGeometry.side)
    }
    public static var iconFrameTop: CGFloat {
        let capTop = buttonsTop - nameBaselineAboveButtons - nameCapHeight
        return capTop - iconGapAboveName + iconFrameSide * iconMarginFraction - iconFrameSide
    }
    public static let recentRowPitch: CGFloat = 47
    public static let recentTextLeading: CGFloat = 56
    public static let recentSeparatorTrailing: CGFloat = 14

    static func nameFont(capHeight: CGFloat = nameCapHeight) -> NSFont {
        let unit = NSFont.systemFont(ofSize: 100, weight: .bold).capHeight / 100
        return .systemFont(ofSize: (capHeight / max(0.01, unit) * 4).rounded() / 4, weight: .bold)
    }

    public let recents: RecentProjects
    public private(set) var entries: [URL] = []

    public let iconView = NSImageView()
    public let nameLabel = NSTextField(labelWithString: "SwiftCode")
    public let versionLabel = NSTextField(labelWithString: "")
    public let openButton = NSButton(title: "Open…", target: nil, action: nil)
    public let cloneButton = NSButton(title: "Clone…", target: nil, action: nil)
    public let newProjectButton = NSPopUpButton(frame: .zero, pullsDown: true)
    public let table = RecentProjectsTable()
    public let closeButton: NSButton = RoundButton()
    public let recentsBox: NSView = RecentsBoxView()
    public let recentsScroll = NSScrollView()
    let emptyLabel = NSTextField(labelWithString: "No Recent Projects")

    public var openWorkspace: (URL, @escaping (Bool) -> Void) -> Void = { url, done in
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            if let error { NSApp.presentError(error) }
            done(doc != nil)
        }
    }
    public var newProjectLocation = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer")
    public var untitledProjectsLocation = UntitledAppProject.defaultLocation
    public var openUntitled: (UntitledAppProject.Created, @escaping (Bool) -> Void) -> Void = { created, done in
        NSDocumentController.shared.openDocument(withContentsOf: created.project, display: true) { doc, _, error in
            if let error { NSApp.presentError(error) }
            for wc in doc?.windowControllers ?? [] { (wc as? WorkspaceWindowController)?.showUntitledProject(entryFile: created.entryFile) }
            done(doc != nil)
        }
    }
    private var recentsObserver: NSObjectProtocol?

    public static var versionText: String { ProductIdentity.versionText }

    public init(recents: RecentProjects = .shared) {
        self.recents = recents
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = Self.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(b)?.isHidden = true }
        super.init(window: window)
        build()
        reload()
        window.center()
        recentsObserver = NotificationCenter.default.addObserver(forName: RecentProjects.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        iconView.image = ProductIcon.image
        iconView.imageScaling = .scaleProportionallyUpOrDown
        nameLabel.font = GlassBars.enabled ? Self.nameFont() : .systemFont(ofSize: 34, weight: .bold)
        nameLabel.alignment = .center
        versionLabel.stringValue = Self.versionText
        versionLabel.font = .systemFont(ofSize: 13)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center

        for (b, action) in [(openButton, #selector(openClicked(_:))), (cloneButton, #selector(cloneClicked(_:)))] {
            b.target = self
            b.action = action
            b.bezelStyle = .push
            b.controlSize = .large
        }
        newProjectButton.controlSize = .large
        newProjectButton.addItem(withTitle: "New Project")
        for (i, row) in NewProjectPicker.rows.enumerated() {
            if i == NewProjectPicker.chooseTemplateIndex { newProjectButton.menu?.addItem(.separator()) }
            let item = NSMenuItem(title: row.title, action: #selector(newProjectChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.toolTip = row.subtitle
            newProjectButton.menu?.addItem(item)
        }
        for b in [openButton, cloneButton] { b.bezelStyle = .flexiblePush }
        newProjectButton.bezelStyle = .flexiblePush
        if #available(macOS 26, *) {
            for b in [openButton, cloneButton] as [NSButton] { b.bezelStyle = .push; b.borderShape = .capsule }
            newProjectButton.bezelStyle = .push
            newProjectButton.borderShape = .capsule
        }
        let buttons = NSStackView(views: [openButton, cloneButton, newProjectButton])
        buttons.orientation = .horizontal
        buttons.spacing = Self.buttonSpacing
        buttons.distribution = .fill
        for (b, w) in zip([openButton, cloneButton, newProjectButton] as [NSView], Self.buttonWidths) {
            b.widthAnchor.constraint(equalToConstant: w).isActive = true
            b.heightAnchor.constraint(equalToConstant: Self.buttonHeight).isActive = true
        }

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        closeButton.imagePosition = .imageOnly
        if #available(macOS 26, *) {
            closeButton.bezelStyle = .glass
            closeButton.borderShape = .circle
            closeButton.isBordered = true
        } else {
            closeButton.isBordered = false
            closeButton.wantsLayer = true
            closeButton.layer?.cornerRadius = Self.closeButtonSize / 2
            closeButton.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Close"
        closeButton.setAccessibilityTitle("Close")
        closeButton.target = self
        closeButton.action = #selector(closeClicked(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = GlassBars.enabled ? Self.recentRowPitch : 44
        if GlassBars.enabled { table.intercellSpacing = NSSize(width: table.intercellSpacing.width, height: 0) }
        table.style = GlassBars.enabled ? .fullWidth : .inset
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected(_:))
        table.onReturn = { [weak self] in self?.openSelected(nil) }
        table.setAccessibilityLabel(Self.recentProjectsTitle)
        let scroll = recentsScroll
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        table.backgroundColor = .clear
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        scroll.translatesAutoresizingMaskIntoConstraints = false
        recentsBox.addSubview(scroll)

        for v in [iconView, nameLabel, versionLabel, buttons, recentsBox, emptyLabel, closeButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: content.topAnchor, constant: GlassBars.enabled ? Self.iconFrameTop : 48),
            iconView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: GlassBars.enabled ? Self.iconFrameSide : 112),
            iconView.heightAnchor.constraint(equalToConstant: GlassBars.enabled ? Self.iconFrameSide : 112),
            GlassBars.enabled
                ? nameLabel.firstBaselineAnchor.constraint(equalTo: content.topAnchor, constant: Self.buttonsTop - Self.nameBaselineAboveButtons)
                : nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            nameLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            GlassBars.enabled
                ? versionLabel.firstBaselineAnchor.constraint(equalTo: content.topAnchor, constant: Self.buttonsTop - Self.versionBaselineAboveButtons)
                : versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            versionLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            buttons.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.buttonsTop),
            buttons.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            GlassBars.enabled ? recentsBox.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.recentsBoxFrame.minY)
                : recentsBox.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 28),
            recentsBox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: GlassBars.enabled ? Self.recentsBoxFrame.minX : 20),
            recentsBox.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: GlassBars.enabled ? Self.recentsBoxFrame.maxX - Self.size.width : -20),
            GlassBars.enabled ? recentsBox.heightAnchor.constraint(equalToConstant: Self.recentsBoxFrame.height)
                : recentsBox.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: recentsBox.topAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: recentsBox.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: recentsBox.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: recentsBox.bottomAnchor, constant: -4),
            emptyLabel.centerXAnchor.constraint(equalTo: recentsBox.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: recentsBox.centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: Self.closeButtonInset),
            closeButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.closeButtonInset),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeButtonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeButtonSize),
        ])
    }

    public func reload() {
        entries = recents.urls
        table.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        if !entries.isEmpty { table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
    }

    public func present() {
        reload()
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard GlassBars.enabled else { return nil }
        let v = RecentRowView()
        v.showsSeparator = row < entries.count - 1
        return v
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let url = entries[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: Self.rowIcon(url))
        let name = NSTextField(labelWithString: RecentProjects.displayName(url))
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.toolTip = name.stringValue
        name.lineBreakMode = .byTruncatingTail
        let folder = NSTextField(labelWithString: RecentProjects.folderText(url))
        folder.font = .systemFont(ofSize: 11)
        folder.textColor = .secondaryLabelColor
        folder.toolTip = folder.stringValue
        folder.lineBreakMode = .byTruncatingHead
        for v in [icon, name, folder] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        cell.textField = name
        cell.imageView = icon
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: GlassBars.enabled ? Self.recentTextLeading - 40 : 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32), icon.heightAnchor.constraint(equalToConstant: 32),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: GlassBars.enabled ? -16 : -4),
            name.bottomAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1),
            folder.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            folder.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: GlassBars.enabled ? -16 : -4),
            folder.topAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1),
        ])
        return cell
    }

    static func rowIcon(_ url: URL) -> NSImage {
        if isPackage(url), let glyph = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Package")?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .regular)) { return glyph }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func isPackage(_ url: URL) -> Bool {
        !["xcodeproj", "xcworkspace"].contains(url.pathExtension)
            && FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path)
    }

    @objc func closeClicked(_ sender: Any?) { window?.performClose(sender) }

    func open(_ url: URL) {
        openWorkspace(url) { [weak self] ok in if ok { self?.close() } }
    }

    @objc public func openSelected(_ sender: Any?) {
        let row = table.clickedRow >= 0 && sender is NSTableView ? table.clickedRow : table.selectedRow
        guard entries.indices.contains(row) else { return }
        open(entries[row])
    }

    @objc func openClicked(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] r in
            guard r == .OK else { return }
            MainActor.assumeIsolated { for u in panel.urls { self?.open(u) } }
        }
    }

    @objc func cloneClicked(_ sender: Any?) {
        let a = NSAlert()
        a.messageText = "Clone"
        a.informativeText = "Enter a repository URL."
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        f.placeholderString = "https://…"
        a.accessoryView = f
        a.addButton(withTitle: "Clone")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Clone"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        clone(f.stringValue, into: dir)
    }

    @discardableResult
    public func clone(_ address: String, into dir: URL) -> Task<Void, Never> {
        let dest = dir.appendingPathComponent(GitRepository.cloneFolderName(for: address))
        let progress = CloneProgressSheet.begin(name: dest.lastPathComponent, on: window)
        return Task { [weak self] in
            let failure: String? = await Task.detached {
                do { try GitRepository.clone(address, into: dest); return nil } catch { return error.localizedDescription }
            }.value
            progress?.end()
            if let failure { NSApp.presentError(NSError(domain: "SwiftCode", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not clone “\(address)”.", NSLocalizedRecoverySuggestionErrorKey: failure])); return }
            if let ws = Self.workspace(in: dest) { self?.open(ws) } else if NSApp.isRunning { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
        }
    }

    public static func workspace(in dir: URL) -> URL? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        if let w = names.first(where: { $0.hasSuffix(".xcworkspace") }) { return dir.appendingPathComponent(w) }
        if let p = names.first(where: { $0.hasSuffix(".xcodeproj") }) { return dir.appendingPathComponent(p) }
        return names.contains("Package.swift") ? dir : nil
    }

    @discardableResult
    @objc func newProjectChosen(_ sender: Any?) -> NewProjectSheetController? {
        guard let i = (sender as? NSMenuItem)?.tag else { return nil }
        if NewProjectPicker.template(forRow: i) == .app {
            createUntitledApp()
            return nil
        }
        return NewProjectFlow.start(row: i, defaults: Preferences.shared.defaults, location: newProjectLocation, parent: window,
                                    interactive: window?.isVisible == true,
                                    onCreated: { [weak self] created in
                                        self?.open(created.openURL)
                                        if let entry = created.entryFile { NewProjectFlow.openEntry(entry, of: created.openURL) }
                                    },
                                    onError: { text in
                                        NSApp.presentError(NSError(domain: "SwiftCode", code: 1, userInfo: [NSLocalizedDescriptionKey: text]))
                                    })
    }
}

extension WelcomeWindowController {
    @discardableResult
    public func createUntitledApp() -> UntitledAppProject.Created? {
        do {
            let created = try UntitledAppProject.create(in: untitledProjectsLocation)
            openUntitled(created) { [weak self] ok in if ok { self?.close() } }
            return created
        } catch {
            NSApp.presentError(error)
            return nil
        }
    }
}

@MainActor
final class CloneProgressSheet {
    private let sheet: NSWindow
    private weak var parent: NSWindow?

    private init(sheet: NSWindow, parent: NSWindow) {
        self.sheet = sheet
        self.parent = parent
    }

    static func begin(name: String, on parent: NSWindow?) -> CloneProgressSheet? {
        guard let parent, parent.isVisible else { return nil }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 84), styleMask: [.titled], backing: .buffered, defer: false)
        let label = NSTextField(labelWithString: "Cloning “\(name)”…")
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let row = NSStackView(views: [spinner, label])
        row.translatesAutoresizingMaskIntoConstraints = false
        w.contentView?.addSubview(row)
        if let c = w.contentView {
            NSLayoutConstraint.activate([row.centerXAnchor.constraint(equalTo: c.centerXAnchor), row.centerYAnchor.constraint(equalTo: c.centerYAnchor)])
        }
        parent.beginSheet(w)
        return CloneProgressSheet(sheet: w, parent: parent)
    }

    func end() { parent?.endSheet(sheet) }
}

extension WorkspaceWindowController {
    public func showUntitledProject(entryFile: URL) {
        open(path: entryFile.path, line: nil)
        inspectorItem?.isCollapsed = true
        if let mac = session.model.destinations.first(where: { $0.kind == .mac }) {
            session.destination = mac
            rememberDestination()
            rebuildDestinationMenu()
        }
        updateToolbarState()
    }
}

final class RecentsBoxView: NSView {
    static let glassCornerRadius: CGFloat = 12
    private var contrastObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        contrastObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        updateLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        if #available(macOS 26, *) {
            layer.cornerRadius = Self.glassCornerRadius
            layer.cornerCurve = .continuous
            layer.backgroundColor = NSColor.quaternarySystemFill.cgColor
            layer.borderWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1 : 0
        } else {
            layer.cornerRadius = 10
            layer.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
            layer.borderWidth = 1
        }
        layer.borderColor = NSColor.separatorColor.cgColor
    }
}

final class RecentRowView: NSTableRowView {
    static let inset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
    var showsSeparator = false { didSet { needsDisplay = true } }

    var separatorRect: NSRect? {
        guard showsSeparator, !isSelected, !isNextRowSelected else { return nil }
        let x = WelcomeWindowController.recentTextLeading
        let w = bounds.width - x - WelcomeWindowController.recentSeparatorTrailing
        guard w > 0 else { return nil }
        return NSRect(x: x, y: isFlipped ? bounds.maxY - 1 : bounds.minY, width: w, height: 1)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard let r = separatorRect else { return }
        NSColor.separatorColor.setFill()
        r.fill()
    }

    override var isNextRowSelected: Bool { didSet { needsDisplay = true } }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        (isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Self.inset, dy: 0), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
    }
}

final class RoundButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }
}

@MainActor
public final class RecentProjectsTable: NSTableView {
    var onReturn: (() -> Void)?
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
    }
}
