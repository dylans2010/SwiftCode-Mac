import AppKit
import YcodeIDECore

@MainActor
public final class InspectorAreaController: NSViewController {
    public static let symbols = WorkspaceChrome.inspectorSymbols
    public static let toolTips = ["Show the File inspector", "Show the History inspector", "Show Quick Help inspector"]
    public var fileInfo: ((URL) -> FileInspectorInfo)?
    public var onSetMembership: ((URL, String, Bool) -> Void)?
    public var historyProvider: ((URL) async -> [GitRepository.Commit])?
    public private(set) var historyLoading: Task<Void, Never>?
    private var loadedHistory: (url: URL, commits: [GitRepository.Commit])?
    private var historyGeneration = 0
    public var onSelectHistoryCommit: ((URL, GitRepository.Commit) -> Void)?
    public var onSearchDocumentation: (() -> Void)?
    public var onChooseLocation: ((URL, URL) -> Void)?
    public private(set) var sectionRuleCount = 0
    public private(set) var innerRuleCount = 0
    public private(set) var shownInfo: FileInspectorInfo?
    public private(set) var historyCommits: [GitRepository.Commit] = []
    public private(set) var selectedMemberships: Set<String> = []
    public var centeredText: String { _ = view; return centerLabel.isHidden ? "" : centerLabel.stringValue }
    private let centerLabel = NSTextField(labelWithString: "")
    public private(set) var sectionTitles: [String] = []
    public private(set) var rowValues: [(String, String)] = []
    public var tabToolTips: [String] { buttons.map { $0.toolTip ?? "" } }
    public private(set) var selectedIndex = 0
    private var buttons: [NSButton] = []
    private let bar = NSStackView()
    let barGlass = GlassBars.capsule()
    let tabPill = SelectionPillView()
    static let tabPillSize = NSSize(width: 78, height: 24)
    var tabBarView: NSView { GlassBars.enabled ? barGlass : bar }

    public override func viewDidLayout() {
        super.viewDidLayout()
        if let sep = contentSeparator {
            let width = isSlidingRigidly ? (guideFixedWidth?.constant ?? view.bounds.width) : view.bounds.width
            let top = view.isFlipped ? sep.frame.maxY : sep.frame.minY
            let frame = view.isFlipped ? NSRect(x: 0, y: top, width: width, height: max(0, view.bounds.height - top))
                : NSRect(x: 0, y: 0, width: width, height: max(0, top))
            if contentScroll.frame != frame { contentScroll.frame = frame }
        }
        if GlassBars.enabled { tabPill.follow(buttons.first { $0.tag == selectedIndex }, size: Self.tabPillSize) }
    }
    public private(set) var extraInspectors: [(name: String, symbol: String)] = []
    private var extraProvider: ((Int) -> NSView)?
    public var onRename: ((URL, String) -> Void)?
    public private(set) var nameField: NSTextField?
    public private(set) var fileControls: [String: NSView] = [:]

    public var tabNames: [String] { CommandTable.inspectors + extraInspectors.map(\.name) }

    public func setExtraInspectors(_ list: [(name: String, symbol: String)], provider: ((Int) -> NSView)?, select index: Int? = nil) {
        let changed = list.map(\.name) != extraInspectors.map(\.name)
        extraInspectors = list
        extraProvider = provider
        guard isViewLoaded else { return }
        if changed { rebuildButtons() }
        if let index { select(index) } else if selectedIndex >= tabNames.count { select(0) } else { select(selectedIndex) }
    }

    public func refresh() { if isViewLoaded { select(selectedIndex) } }

    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        let all = zip(CommandTable.inspectors, Self.symbols).map { ($0, $1) } + extraInspectors.map { ($0.name, $0.symbol) }
        for (i, (name, symbol)) in all.enumerated() {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: "\(name) inspector") ?? NSImage(),
                             target: self, action: #selector(tabClicked(_:)))
            b.isBordered = false
            b.tag = i
            b.toolTip = i < Self.toolTips.count ? Self.toolTips[i] : "Show the \(name) inspector"
            buttons.append(b)
            bar.addArrangedSubview(b)
        }
    }
    private let content = NSStackView()
    let contentScroll = NSScrollView()
    private var file: URL?
    public private(set) var quickHelp: String?

    public var quickHelpFile: String?

    public func showQuickHelp(_ text: String?, file: String? = nil) {
        quickHelp = text
        quickHelpFile = file
        if selectedIndex == 2 { select(2) }
    }

    public override func loadView() {
        let root = NSView()
        root.clipsToBounds = true
        root.addLayoutGuide(slideGuide)
        guideFollowsArea = slideGuide.widthAnchor.constraint(equalTo: root.widthAnchor)
        guideFixedWidth = slideGuide.widthAnchor.constraint(equalToConstant: 260)
        NSLayoutConstraint.activate([
            slideGuide.leadingAnchor.constraint(equalTo: root.leadingAnchor), slideGuide.topAnchor.constraint(equalTo: root.topAnchor),
            slideGuide.bottomAnchor.constraint(equalTo: root.bottomAnchor), guideFollowsArea!,
        ])
        bar.orientation = .horizontal
        bar.distribution = .fillEqually
        bar.spacing = 0
        rebuildButtons()
        let sep = NSBox.hairline()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        content.edgeInsets = NSEdgeInsets(top: Self.contentTopInset, left: Self.leadingInset, bottom: Self.contentTopInset, right: Self.trailingInset)
        centerLabel.textColor = .secondaryLabelColor
        centerLabel.alignment = .center
        centerLabel.font = .systemFont(ofSize: 13)
        centerLabel.isHidden = true
        let divider = NSBox()
        divider.boxType = .separator
        let glass = GlassBars.enabled
        contentScroll.drawsBackground = false
        contentScroll.automaticallyAdjustsContentInsets = false
        contentScroll.contentInsets = NSEdgeInsets()
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.scrollerStyle = .overlay
        let doc = InspectorDocumentView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.documentView = doc
        content.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: doc.topAnchor), content.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: doc.leadingAnchor), content.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            doc.topAnchor.constraint(equalTo: contentScroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: contentScroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
        ])
        for v in [bar, sep, contentScroll, centerLabel, divider] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        if glass {
            barGlass.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(barGlass, positioned: .below, relativeTo: bar)
            root.addSubview(tabPill, positioned: .below, relativeTo: bar)
            sep.alphaValue = 0
            NSLayoutConstraint.activate([
                barGlass.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: GlassBars.topOffset),
                barGlass.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 5),
                barGlass.trailingAnchor.constraint(equalTo: slideGuide.trailingAnchor, constant: -6),
                barGlass.heightAnchor.constraint(equalToConstant: GlassBars.height),
            ])
        }
        let below = NSLayoutGuide()
        root.addLayoutGuide(below)
        NSLayoutConstraint.activate([
            below.topAnchor.constraint(equalTo: glass ? barGlass.bottomAnchor : sep.bottomAnchor),
            below.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            centerLabel.centerYAnchor.constraint(equalTo: below.centerYAnchor),
        ])
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: glass ? GlassBars.topOffset + 2 : 4),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: glass ? 10 : 8),
            bar.trailingAnchor.constraint(equalTo: slideGuide.trailingAnchor, constant: glass ? -10 : -8),
            bar.heightAnchor.constraint(equalToConstant: 26),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            centerLabel.centerXAnchor.constraint(equalTo: slideGuide.centerXAnchor),
            sep.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 2),
            sep.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: slideGuide.trailingAnchor),
        ])
        contentScroll.translatesAutoresizingMaskIntoConstraints = true
        contentSeparator = sep
        view = root
        select(0)
    }

    private let slideGuide = NSLayoutGuide()
    private weak var contentSeparator: NSView?
    private var guideFollowsArea: NSLayoutConstraint?
    private var guideFixedWidth: NSLayoutConstraint?
    public private(set) var isSlidingRigidly = false

    public func beginRigidSlide(width: CGFloat) {
        _ = view
        isSlidingRigidly = true
        guideFollowsArea?.isActive = false
        guideFixedWidth?.constant = width
        guideFixedWidth?.isActive = true
    }

    public func endRigidSlide() {
        isSlidingRigidly = false
        guideFixedWidth?.isActive = false
        guideFollowsArea?.isActive = true
    }

    public func show(file: URL?) {
        if file != self.file { selectedMemberships = [] }
        self.file = file
        select(selectedIndex)
    }

    public func select(_ index: Int) {
        selectedIndex = index
        for b in buttons { b.contentTintColor = TabGlyphTint.color(selected: b.tag == index) }
        if isViewLoaded { view.needsLayout = true }
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.edgeInsets.top = Self.contentTopInset
        centerLabel.isHidden = true
        sectionTitles = []
        sectionRuleCount = 0
        innerRuleCount = 0
        rowValues = []
        if index >= CommandTable.inspectors.count, let provider = extraProvider {
            let v = provider(index - CommandTable.inspectors.count)
            content.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
            return
        }
        switch index {
        case 0: fileInspector()
        case 1: historyInspector()
        default:
            if let q = quickHelp {
                content.addArrangedSubview(QuickHelpView.make(QuickHelpDocument(hover: q, file: quickHelpFile)))
            } else {
                content.addArrangedSubview(heading("Quick Help"))
                let none = note("No Quick Help")
                none.alignment = .center
                let search = NSButton(title: "Search Documentation", target: self, action: #selector(searchDocumentationClicked))
                search.controlSize = .small
                search.font = .systemFont(ofSize: 11)
                fileControls["Search Documentation"] = search
                fileControls["No Quick Help"] = none
                let centered = NSStackView(views: [none, search])
                centered.orientation = .vertical
                centered.alignment = .centerX
                centered.spacing = 6
                content.addArrangedSubview(centered)
                centered.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
                addRule()
            }
        }
    }

    @objc private func searchDocumentationClicked() { onSearchDocumentation?() }

    private func showCentered(_ text: String) {
        centerLabel.stringValue = text
        centerLabel.isHidden = false
    }

    public func historyIdle() async {
        while let t = historyLoading { await t.value }
    }

    private func historyInspector() {
        historyGeneration += 1
        if let loaded = loadedHistory, loaded.url == file {
            loadedHistory = nil
            historyLoading = nil
            historyCommits = loaded.commits
        } else if let file, let provider = historyProvider {
            loadedHistory = nil
            historyCommits = []
            let generation = historyGeneration
            historyLoading = Task { [weak self] in
                let commits = await provider(file)
                guard let self, generation == self.historyGeneration else { return }
                self.historyLoading = nil
                guard self.selectedIndex == 1, self.file == file else { return }
                self.loadedHistory = (file, commits)
                self.select(1)
            }
            return
        } else {
            historyCommits = []
        }
        historyRowViews = []
        guard !historyCommits.isEmpty else { showCentered("No History"); return }
        for (i, c) in historyCommits.enumerated() {
            let author = NSTextField(labelWithString: c.authorName)
            author.font = .boldSystemFont(ofSize: 11)
            author.lineBreakMode = .byTruncatingTail
            let subject = NSTextField(labelWithString: c.subject)
            subject.font = .systemFont(ofSize: 11)
            subject.textColor = .secondaryLabelColor
            subject.lineBreakMode = .byTruncatingTail
            let hash = NSTextField(labelWithString: c.shortHash)
            hash.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            hash.textColor = .secondaryLabelColor
            hash.alignment = .right
            let date = NSTextField(labelWithString: GitDates.relativeDay(c.date))
            date.font = .systemFont(ofSize: 10)
            date.textColor = .secondaryLabelColor
            date.alignment = .right
            let left = NSStackView(views: [author, subject])
            left.orientation = .vertical
            left.alignment = .leading
            left.spacing = 1
            left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            for l in [author, subject] { l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
            let right = NSStackView(views: [hash, date])
            right.orientation = .vertical
            right.alignment = .trailing
            right.spacing = 1
            for v in [right, hash, date] as [NSView] {
                v.setContentHuggingPriority(.required, for: .horizontal)
                v.setContentCompressionResistancePriority(.required, for: .horizontal)
            }
            let top = NSStackView(views: [left, NSView(), right])
            top.alignment = .top
            let rowView = NSStackView(views: [top])
            rowView.orientation = .vertical
            rowView.alignment = .leading
            rowView.spacing = 1
            historyRowViews.append((left: left, right: right))
            let button = NSButton(title: "", target: self, action: #selector(historyRowClicked(_:)))
            button.isBordered = false
            button.isTransparent = true
            button.tag = i
            button.setAccessibilityLabel("\(c.authorName), \(c.subject)")
            button.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: rowView.leadingAnchor), button.trailingAnchor.constraint(equalTo: rowView.trailingAnchor),
                button.topAnchor.constraint(equalTo: rowView.topAnchor), button.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            ])
            content.addArrangedSubview(rowView)
            rowView.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
            top.widthAnchor.constraint(equalTo: rowView.widthAnchor).isActive = true
            rowValues.append((c.authorName, c.subject))
        }
    }

    public var historyRows: [(author: String, subject: String, date: String, hash: String)] {
        historyCommits.map { ($0.authorName, $0.subject, GitDates.relativeDay($0.date), $0.shortHash) }
    }
    public private(set) var historyRowViews: [(left: NSStackView, right: NSStackView)] = []

    @objc private func historyRowClicked(_ b: NSButton) { selectHistoryRow(b.tag) }

    public func selectHistoryRow(_ i: Int) {
        guard let file, i >= 0, i < historyCommits.count else { return }
        onSelectHistoryCommit?(file, historyCommits[i])
    }

    private func fileInspector() {
        guard let file else {
            showCentered("Not Applicable")
            return
        }
        fileControls = [:]
        content.edgeInsets.top = Self.contentTopInset - InspectorStyle.firstHeadingRaise
        let identity = heading("Identity and Type")
        content.addArrangedSubview(identity)
        content.setCustomSpacing(InspectorStyle.firstHeadingRaise, after: identity)
        let name = NSTextField(string: file.lastPathComponent)
        name.font = .systemFont(ofSize: 11)
        InspectorStyle.fill(name)
        name.target = self
        name.action = #selector(nameCommitted(_:))
        name.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        nameField = name
        content.addArrangedSubview(row("Name", name))
        let typeRow = row("Type", popUp("Type", ["Default - " + Self.typeName(for: file)]))
        content.addArrangedSubview(typeRow)
        let typeRule = addInnerRule()
        content.setCustomSpacing(0, after: typeRow)
        content.setCustomSpacing(InspectorStyle.afterTypeRule, after: typeRule)
        let info = fileInfo?(file) ?? FileInspectorInfo()
        shownInfo = info
        let choose = NSButton(image: NSImage(systemSymbolName: "folder", accessibilityDescription: "Choose location")!, target: self,
                              action: #selector(chooseLocationClicked))
        choose.isBordered = false
        choose.toolTip = "Choose location"
        let isProject = file.pathExtension == "xcodeproj"
        let location = popUp("Location", [isProject ? "Absolute" : "Relative to Group"])
        location.isEnabled = !isProject && !info.inSynchronizedFolder
        choose.isEnabled = !isProject
        choose.isHidden = info.inSynchronizedFolder
        fileControls["Choose Location"] = choose
        let locationRow = row("Location", NSStackView(views: [location, choose]))
        content.addArrangedSubview(locationRow)
        content.setCustomSpacing(InspectorStyle.afterLocation, after: locationRow)
        if isProject { content.addArrangedSubview(row("", note("Containing directory"))) }
        let fileName = NSTextField(labelWithString: file.lastPathComponent)
        fileName.font = .systemFont(ofSize: 11)
        let fileNameRow = row("", fileName)
        content.addArrangedSubview(fileNameRow)
        content.setCustomSpacing(InspectorStyle.fileNameToPath, after: fileNameRow)
        let path = InspectorStyle.pathLabel(file.path)
        path.preferredMaxLayoutWidth = 140
        let reveal = NSButton(image: NSImage(systemSymbolName: "arrow.right.circle.fill", accessibilityDescription: "Show in Finder")!,
                              target: self, action: #selector(revealClicked))
        reveal.isBordered = false
        fileControls["Reveal"] = reveal
        let pathStack = NSStackView(views: [path, reveal])
        pathStack.alignment = .top
        let fullPath = row("Full Path", pathStack)
        (fullPath as? NSStackView)?.alignment = .firstBaseline
        content.addArrangedSubview(fullPath)
        rowValues.append(("Full Path", file.path))
        let pathRule = addInnerRule()
        if let wc = info.workingCopy, let rel = info.relativePath {
            for (k, v) in [("Working Copy", wc), ("Relative Path", rel)] {
                content.addArrangedSubview(row(k, v))
                rowValues.append((k, v))
            }
        }
        if isProject {
            let rows = ProjectDocumentInspector.rows(for: file, controls: &fileControls)
            if !rows.isEmpty {
                content.addArrangedSubview(heading("Project Document"))
                for (k, v) in rows { content.addArrangedSubview(row(k, v)) }
            }
        }
        let isImage = ImageViewerController.handles(file)
        if !isProject && !info.isPackageFile {
            onDemandResourceTags(resource: isImage)
            if let i = content.arrangedSubviews.firstIndex(of: pathRule), i + 1 < content.arrangedSubviews.count,
               content.arrangedSubviews[i + 1] is NSBox {
                content.setCustomSpacing(InspectorStyle.pathRuleToTagsRule, after: pathRule)
            }
            if isImage { imageSections() }
            targetMembership(file, info)
        }
        guard !isImage else { return }
        content.addArrangedSubview(heading("Text Settings"))
        for (key, items) in [("Text Encoding", WorkspaceChrome.textEncodingItems), ("Line Endings", WorkspaceChrome.lineEndingItems)] {
            let pop = popUp(key, items)
            InspectorStyle.dimFirstTitle(pop)
            content.addArrangedSubview(row(key, pop))
        }
        addInnerRule()
        let p = Preferences.shared
        let config = editorConfig(file)
        shownEditorConfig = config
        let tabs = config.indentStyle.map { $0 == .tab } ?? p.indentWithTabs
        let indent = popUp("Indent Using", tabs ? ["Tabs", "Spaces"] : ["Spaces", "Tabs"])
        content.addArrangedSubview(row("Indent Using", indent))
        let tab = stepper("Tab", config.tabWidth ?? p.tabWidth), ind = stepper("Indent", config.indentSize ?? p.indentWidth)
        content.addArrangedSubview(row("Widths", NSStackView(views: [tab, ind])))
        if config.providesIndentation {
            indent.isEnabled = false
            for k in ["Tab", "Indent"] { (fileControls[k] as? NSControl)?.isEnabled = false }
            for k in ["Tab Value", "Indent Value"] { (fileControls[k] as? NSTextField)?.textColor = .disabledControlTextColor }
            let note = NSTextField(wrappingLabelWithString: EditorConfig.indentationNote)
            note.font = .systemFont(ofSize: 11)
            note.preferredMaxLayoutWidth = 150
            fileControls["EditorConfig Note"] = note
            content.addArrangedSubview(row("", note))
        }
    }

    public var editorConfig: (URL) -> EditorConfig = { EditorConfig.settings(for: $0) }
    public private(set) var shownEditorConfig: EditorConfig?

    private func popUp(_ key: String, _ items: [String]) -> NSPopUpButton {
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        b.addItems(withTitles: items)
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        InspectorStyle.fill(b)
        fileControls[key] = b
        return b
    }

    private func stepper(_ label: String, _ value: Int) -> NSView {
        let field = NSTextField(labelWithString: "\(value)")
        field.font = .systemFont(ofSize: 11)
        let s = NSStepper()
        s.minValue = 1
        s.maxValue = 16
        s.integerValue = value
        s.controlSize = .small
        s.target = self
        s.action = #selector(stepped(_:))
        s.identifier = .init(label)
        fileControls[label] = s
        fileControls[label + " Value"] = field
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 9)
        l.textColor = .secondaryLabelColor
        let col = NSStackView(views: [NSStackView(views: [field, s]), l])
        col.orientation = .vertical
        col.spacing = 1
        return col
    }

    @objc private func stepped(_ s: NSStepper) {
        let key = s.identifier?.rawValue ?? ""
        (fileControls[key + " Value"] as? NSTextField)?.stringValue = "\(s.integerValue)"
        if key == "Tab" { Preferences.shared.tabWidth = s.integerValue } else { Preferences.shared.indentWidth = s.integerValue }
    }

    @objc private func nameCommitted(_ f: NSTextField) {
        guard let file, !f.stringValue.isEmpty, f.stringValue != file.lastPathComponent else { return }
        onRename?(file, f.stringValue)
    }

    @objc private func chooseLocationClicked() {
        guard let file, let window = view.window, window.isVisible else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = file.deletingLastPathComponent()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.onChooseLocation?(file, url) }
        }
    }

    @objc private func revealClicked() {
        guard let file, view.window?.isVisible == true else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    static func typeName(for url: URL) -> String { WorkspaceChrome.fileTypeName(for: url) }

    public var imageProperties: ImageFileProperties? {
        didSet { if oldValue != imageProperties, selectedIndex == 0 { refresh() } }
    }

    private func imageSections() {
        content.addArrangedSubview(heading("Image Properties"))
        for (k, v) in imageProperties?.rows ?? ImageFileProperties.placeholderRows {
            content.addArrangedSubview(row(k, v))
            rowValues.append((k, v))
        }
        content.addArrangedSubview(heading("Localization"))
        let localize = NSButton(title: "Localize…", target: nil, action: nil)
        localize.controlSize = .small
        localize.font = .systemFont(ofSize: 11)
        localize.isBordered = false
        localize.alignment = .center
        localize.wantsLayer = true
        localize.layer?.cornerRadius = 5
        localize.layer?.cornerCurve = .continuous
        localize.layer?.backgroundColor = InspectorStyle.popUpFill.cgColor
        localize.heightAnchor.constraint(equalToConstant: 16).isActive = true
        fileControls["Localize"] = localize
        content.addArrangedSubview(localize)
        localize.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
    }

    private func onDemandResourceTags(resource: Bool = false) {
        content.addArrangedSubview(heading("On Demand Resource Tags"))
        let tags = NSTokenField()
        tags.placeholderString = resource ? "Tags" : "Only resources are taggable"
        tags.isEnabled = resource
        if resource {
            tags.isBezeled = false
            tags.isBordered = false
            tags.drawsBackground = false
            tags.wantsLayer = true
            tags.layer?.cornerRadius = 6
            tags.layer?.backgroundColor = InspectorStyle.fieldFill.cgColor
            tags.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        tags.controlSize = .small
        tags.font = .systemFont(ofSize: 11)
        fileControls["On Demand Resource Tags"] = tags
        content.addArrangedSubview(tags)
        tags.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
    }

    private func targetMembership(_ file: URL, _ info: FileInspectorInfo) {
        guard !info.memberships.isEmpty else { return }
        let tags = fileControls["On Demand Resource Tags"]
        let afterTags = tags != nil && content.arrangedSubviews.last === tags
        content.addArrangedSubview(heading("Target Membership"))
        if afterTags, let tags { content.setCustomSpacing(InspectorStyle.ruleGap + InspectorStyle.tagsBoxExtra, after: tags) }
        let members = info.memberships.filter(\.isMember)
        selectedMemberships.formIntersection(members.map(\.targetID))
        let table = NSStackView()
        table.orientation = .vertical
        table.alignment = .leading
        table.spacing = 2
        table.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 0, right: 4)
        table.wantsLayer = true
        table.layer?.borderWidth = 1
        table.layer?.cornerRadius = 0
        table.layer?.borderColor = InspectorStyle.tableBorder.cgColor
        table.heightAnchor.constraint(greaterThanOrEqualToConstant: InspectorStyle.membershipTableHeight).isActive = true
        fileControls["Target Membership Table"] = table
        for m in members {
            let name = NSTextField(labelWithString: m.name)
            name.font = .systemFont(ofSize: 11)
            let kind = NSTextField(labelWithString: m.kind)
            kind.font = .systemFont(ofSize: 10)
            kind.textColor = .secondaryLabelColor
            let text = NSStackView(views: [name, kind])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 0
            let icon = NSImageView(image: InspectorStyle.targetIcon())
            icon.setAccessibilityLabel("Target")
            let r = NSStackView(views: [icon, text])
            r.wantsLayer = true
            r.layer?.cornerRadius = 4
            r.layer?.backgroundColor = selectedMemberships.contains(m.targetID) ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).cgColor : nil
            let pick = NSButton(title: "", target: self, action: #selector(membershipRowClicked(_:)))
            pick.isBordered = false
            pick.isTransparent = true
            pick.identifier = .init(m.targetID)
            pick.setAccessibilityLabel(m.name)
            pick.translatesAutoresizingMaskIntoConstraints = false
            r.addSubview(pick)
            NSLayoutConstraint.activate([
                pick.leadingAnchor.constraint(equalTo: r.leadingAnchor), pick.trailingAnchor.constraint(equalTo: r.trailingAnchor),
                pick.topAnchor.constraint(equalTo: r.topAnchor), pick.bottomAnchor.constraint(equalTo: r.bottomAnchor),
            ])
            table.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: table.widthAnchor, constant: -8).isActive = true
            rowValues.append(("Target", m.name))
        }
        func small(_ symbol: String, _ tip: String, _ sel: Selector?) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self, action: sel)
            b.isBordered = false
            b.toolTip = tip
            b.isEnabled = sel != nil
            return b
        }
        let add = small("plus", "Choose which targets include this file", #selector(addMembershipClicked(_:)))
        add.isEnabled = true
        let remove = small("minus", "Remove this file from selected targets", #selector(removeMembershipClicked))
        remove.isEnabled = info.memberships.contains { selectedMemberships.contains($0.targetID) && $0.isEditable }
        let edit = small("pencil", "Edit target membership options", nil)
        fileControls["Add Target"] = add
        fileControls["Remove Target"] = remove
        fileControls["Edit Target Membership"] = edit
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        table.addArrangedSubview(spacer)
        let rule = NSBox.hairline()
        table.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: table.widthAnchor).isActive = true
        var footer: [NSView] = []
        for b in [add, remove, edit] {
            if !footer.isEmpty {
                let line = NSBox()
                line.boxType = .separator
                line.heightAnchor.constraint(equalToConstant: 13).isActive = true
                footer.append(line)
            }
            b.widthAnchor.constraint(equalToConstant: 20).isActive = true
            footer.append(b)
        }
        let buttons = NSStackView(views: footer)
        buttons.spacing = 2
        buttons.heightAnchor.constraint(equalToConstant: InspectorStyle.membershipFooterHeight).isActive = true
        table.addArrangedSubview(buttons)
        table.setCustomSpacing(0, after: rule)
        table.setCustomSpacing(0, after: spacer)
        content.addArrangedSubview(table)
        table.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
    }

    @objc private func membershipRowClicked(_ b: NSButton) {
        guard let id = b.identifier?.rawValue else { return }
        toggleMembershipSelection(id)
    }

    public func toggleMembershipSelection(_ targetID: String) {
        if !selectedMemberships.insert(targetID).inserted { selectedMemberships.remove(targetID) }
        refresh()
    }

    public func addMembershipMenu() -> NSMenu {
        let menu = NSMenu(title: "Targets")
        defer {
            if menu.items.isEmpty {
                let none = NSMenuItem(title: "No Other Targets", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
            }
        }
        for m in shownInfo?.memberships ?? [] where !m.isMember {
            let item = NSMenuItem(title: m.name, action: m.isEditable ? #selector(addMembershipChosen(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.representedObject = m.targetID
            item.isEnabled = m.isEditable
            menu.addItem(item)
        }
        return menu
    }

    @objc private func addMembershipClicked(_ b: NSButton) {
        let menu = addMembershipMenu()
        guard b.window?.isVisible == true else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.bounds.height), in: b)
    }

    @objc private func addMembershipChosen(_ item: NSMenuItem) {
        guard let file, let id = item.representedObject as? String else { return }
        onSetMembership?(file, id, true)
        refresh()
    }

    @objc public func removeMembershipClicked() {
        guard let file else { return }
        for id in selectedMemberships.sorted() { onSetMembership?(file, id, false) }
        selectedMemberships = []
        refresh()
    }

    private func heading(_ s: String) -> NSView {
        if !sectionTitles.isEmpty { addRule() }
        sectionTitles.append(s)
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 11)
        l.textColor = InspectorStyle.headingColor
        return InspectorRowBox(l, height: InspectorStyle.headingRowHeight, inset: -1)
    }

    @discardableResult
    private func addInnerRule() -> NSView {
        if let last = content.arrangedSubviews.last { content.setCustomSpacing(InspectorStyle.ruleGap, after: last) }
        let rule = NSBox.hairline()
        content.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
        content.setCustomSpacing(InspectorStyle.ruleGap, after: rule)
        innerRuleCount += 1
        return rule
    }

    private func addRule() {
        if let last = content.arrangedSubviews.last { content.setCustomSpacing(InspectorStyle.ruleGap, after: last) }
        let rule = NSBox.hairline()
        content.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -Self.horizontalInsets).isActive = true
        content.setCustomSpacing(InspectorStyle.ruleGap, after: rule)
        sectionRuleCount += 1
    }

    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func row(_ key: String, _ control: NSView) -> NSView {
        let s = InspectorRowView(views: [keyLabel(key), control])
        s.alignment = .centerY
        s.spacing = InspectorStyle.keyToValue
        let pitch: CGFloat = control is NSPopUpButton || (control as? NSStackView)?.arrangedSubviews.first is NSPopUpButton ? 22
            : ((control as? NSTextField)?.isEditable == true ? 26 : 0)
        if pitch > 0 { s.heightAnchor.constraint(equalToConstant: pitch).isActive = true }
        let fills = control is NSPopUpButton || (control is NSTextField && (control as? NSTextField)?.isEditable == true)
            || ((control as? NSStackView)?.arrangedSubviews.first is NSPopUpButton)
        if fills {
            s.distribution = .fill
            control.trailingAnchor.constraint(equalTo: s.trailingAnchor).isActive = true
            control.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
            control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if let inner = control as? NSStackView, let pop = inner.arrangedSubviews.first {
                inner.distribution = .fill
                pop.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
                pop.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
        }
        return s
    }

    private func row(_ key: String, _ value: String) -> NSView {
        let v = InspectorStyle.pathLabel(value)
        v.preferredMaxLayoutWidth = 160
        let s = InspectorRowView(views: [keyLabel(key), v])
        s.alignment = .firstBaseline
        s.spacing = InspectorStyle.keyToValue
        s.edgeInsets = NSEdgeInsets(top: 3, left: 0, bottom: 3, right: 0)
        return s
    }

    private func keyLabel(_ key: String) -> NSTextField {
        let k = NSTextField(labelWithString: key)
        k.font = .systemFont(ofSize: 11)
        k.textColor = .labelColor
        k.alignment = .right
        k.lineBreakMode = .byClipping
        k.attributedStringValue = InspectorStyle.fitted(key, font: k.font!, width: Self.keyColumnWidth)
        k.widthAnchor.constraint(equalToConstant: Self.keyColumnWidth).isActive = true
        k.setContentCompressionResistancePriority(.required, for: .horizontal)
        return k
    }

    static let leadingInset: CGFloat = 7
    static let trailingInset: CGFloat = 8
    static var horizontalInsets: CGFloat { leadingInset + trailingInset }
    static let contentInset: CGFloat = 8
    static let contentTopInset: CGFloat = 4
    static let keyColumnWidth: CGFloat = 72

    @objc private func tabClicked(_ b: NSButton) { select(b.tag) }
}

final class InspectorRowView: NSStackView {
    private var widthConstraint: NSLayoutConstraint?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        widthConstraint?.isActive = false
        widthConstraint = nil
        guard let sup = superview else { return }
        let c = widthAnchor.constraint(equalTo: sup.widthAnchor, constant: -InspectorAreaController.horizontalInsets)
        c.isActive = true
        widthConstraint = c
    }
}

final class InspectorDocumentView: NSView {
    override var isFlipped: Bool { true }
}
