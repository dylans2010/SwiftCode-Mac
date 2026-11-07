import AppKit
import SwiftCodeBuild
import SwiftCodeCompletion
import SwiftCodeIDECore
import SwiftCodeLanguage

@MainActor
final class SourceTextView: NSTextView {
    override func viewDidEndLiveResize() {
        guard let scroll = enclosingScrollView else { return super.viewDidEndLiveResize() }
        let clip = scroll.contentView
        let before = clip.bounds.origin
        super.viewDidEndLiveResize()
        guard clip.bounds.origin != before else { return }
        let kept = clip.constrainBoundsRect(NSRect(origin: before, size: clip.bounds.size)).origin
        clip.scroll(to: kept)
        scroll.reflectScrolledClipView(clip)
    }

    var issues: [Int: [Diagnostic]] = [:] { didSet { needsDisplay = true } }
    var issuesStale = false { didSet { if oldValue != issuesStale { needsDisplay = true } } }
    var showsIssues = true { didSet { needsDisplay = true } }
    var reviewMarks: [Int: LineDiff.Row.Kind] = [:] { didSet { needsDisplay = true } }
    var findMatches: [NSRange] = [] { didSet { needsDisplay = true } }
    var foldedStartLines: Set<Int> = [] { didSet { needsDisplay = true } }
    var currentFindMatch: NSRange? { didSet { needsDisplay = true } }
    let displayState = EditorDisplayState()
    var ghostText: GhostText? { didSet { if oldValue != ghostText { updateGhostOverlay() } } }
    let ghostOverlay = GhostTextOverlay()

    @objc func showPredictiveCompletion(_ sender: Any?) { owner?.showPredictiveCompletion(sender) }

    override func flagsChanged(with event: NSEvent) {
        owner?.predictionFlagsChanged(event)
        super.flagsChanged(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: newSize.width, height: heightWithOverscroll(newSize.height)))
    }

    override func performFindPanelAction(_ sender: Any?) {
        if owner?.performFind(tag: (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag ?? 1) != true {
            super.performFindPanelAction(sender)
        }
    }

    override func delete(_ sender: Any?) {
        if selectedRange().length == 0 { deleteToBeginningOfLine(sender) } else { super.delete(sender) }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(delete(_:)) ? isEditable : super.validateMenuItem(item)
    }

    func segmentRects(_ range: NSRange) -> [NSRect] {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager,
              let start = tcm.location(tcm.documentRange.location, offsetBy: range.location),
              let end = tcm.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return [] }
        tlm.ensureLayout(for: textRange)
        var rects: [NSRect] = []
        tlm.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
            rects.append(frame.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
            return true
        }
        return rects
    }
    var highlightedLine: Int? { didSet { needsDisplay = true } }
    var stopAnnotation: String? { didSet { needsDisplay = true } }
    var caretLine: Int? {
        didSet {
            guard oldValue != caretLine else { return }
            for l in [oldValue, caretLine].compactMap({ $0 }) {
                if let r = lineRect(l) { setNeedsDisplay(r.insetBy(dx: 0, dy: -1)) } else { needsDisplay = true }
            }
        }
    }
    var lineIndex = LineIndex("")
    weak var owner: SourceEditorController?

    override func mouseDown(with event: NSEvent) {
        if let action = Preferences.shared.codeClick(for: event.modifierFlags) {
            let p = convert(event.locationInWindow, from: nil)
            let offset = characterIndexForInsertion(at: p)
            if action == .quickHelp { owner?.quickHelp(atOffset: offset) } else { owner?.jumpToDefinition(atOffset: offset) }
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if let line = owner?.annotationLine(at: p), let menu = owner?.fixItMenu(line: line) {
            menu.popUp(positioning: nil, at: p, in: self)
            return
        }
        super.mouseDown(with: event)
        let s = selectedRange()
        if s.length == 0, let t = Placeholders.token(containing: s.location, in: string) { setSelectedRange(t) }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !keepsMultipleRanges && !multipleRanges.isEmpty { multipleRanges = [] }
        needsDisplay = true
    }

    var multipleRanges: [NSRange] = [] { didSet { needsDisplay = true } }
    private var keepsMultipleRanges = false

    func setMultipleRanges(_ ranges: [NSRange], primary: NSRange? = nil) {
        var sorted: [NSRange] = []
        for r in ranges.sorted(by: { ($0.location, $0.length) < ($1.location, $1.length) }) where sorted.last.map({ NSMaxRange($0) <= r.location && $0 != r }) ?? true {
            sorted.append(r)
        }
        guard let last = sorted.last else { return }
        keepsMultipleRanges = true
        setSelectedRange(primary ?? last)
        keepsMultipleRanges = false
        multipleRanges = sorted.count > 1 ? sorted : []
    }

    func editEachSelection(_ edit: (NSRange) -> (NSRange, String)?) {
        let edits = multipleRanges.compactMap(edit)
        guard !edits.isEmpty else { return }
        keepsMultipleRanges = true
        undoManager?.beginUndoGrouping()
        for (r, s) in edits.reversed() where shouldChangeText(in: r, replacementString: s) {
            replaceCharacters(in: r, with: s)
            didChangeText()
        }
        undoManager?.endUndoGrouping()
        var carets: [NSRange] = []
        var delta = 0
        for (r, s) in edits {
            let n = (s as NSString).length
            carets.append(NSRange(location: r.location + delta + n, length: 0))
            delta += n - r.length
        }
        setSelectedRange(carets[carets.count - 1])
        keepsMultipleRanges = false
        multipleRanges = carets.count > 1 ? carets : []
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let s = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        if multipleRanges.count > 1, replacementRange.location == NSNotFound {
            editEachSelection { ($0, s) }
            return
        }
        let typed = replacementRange.location == NSNotFound && !hasMarkedText()
        if typed, owner?.typeCharacter(s) == true { return }
        super.insertText(string, replacementRange: replacementRange)
        if typed { owner?.didTypeCharacter(s) }
    }

    override func insertNewline(_ sender: Any?) {
        if owner?.typeNewline() == true { return }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        guard multipleRanges.count > 1 else {
            if owner?.deleteAutomaticPair() == true { return }
            super.deleteBackward(sender)
            return
        }
        editEachSelection { r in r.length > 0 ? (r, "") : (r.location > 0 ? (NSRange(location: r.location - 1, length: 1), "") : nil) }
    }

    override func cancelOperation(_ sender: Any?) {
        if !multipleRanges.isEmpty { multipleRanges = []; return }
        _ = nextResponder?.tryToPerform(#selector(cancelOperation(_:)), with: sender)
    }

    func drawMultipleRanges(in rect: NSRect) {
        let primary = selectedRange()
        for r in multipleRanges where r != primary {
            if r.length > 0 {
                Theme.selectionColor.setFill()
                for seg in segmentRects(r) where seg.intersects(rect) { seg.fill() }
            } else if let c = caretRect(at: r.location), c.intersects(rect) {
                insertionPointColor.setFill()
                NSRect(x: c.minX, y: c.minY, width: 1.5, height: c.height).fill()
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { owner?.onActivate?() }
        return ok
    }

    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: range, replacementString: replacementString)
        if ok {
            owner?.noteEdit(range: range, replacement: replacementString ?? "")
            owner?.notePredictionEdit(range: range, replacement: replacementString ?? "")
            owner?.noteSyntaxEdit(range: range, replacement: replacementString)
        }
        return ok
    }

    override func keyDown(with event: NSEvent) {
        if owner?.handleCompletionKey(event) == true { return }
        if owner?.handlePredictionKey(event) == true { return }
        if owner?.handlePlaceholderKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func complete(_ sender: Any?) { owner?.requestCompletion() }

    func caretRect(at offset: Int) -> NSRect? {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager,
              let loc = tcm.location(tcm.documentRange.location, offsetBy: offset) else { return nil }
        tlm.ensureLayout(for: NSTextRange(location: tcm.documentRange.location, end: loc) ?? tlm.documentRange)
        guard let frag = tlm.textLayoutFragment(for: loc) else { return nil }
        let fragStart = tcm.offset(from: tcm.documentRange.location, to: frag.rangeInElement.location)
        let inFrag = offset - fragStart
        let origin = frag.layoutFragmentFrame.origin
        for line in frag.textLineFragments {
            let r = line.characterRange
            if inFrag >= r.location && inFrag <= NSMaxRange(r) {
                let p = line.locationForCharacter(at: inFrag)
                let b = line.typographicBounds
                return NSRect(x: origin.x + b.minX + p.x + textContainerOrigin.x,
                              y: origin.y + b.minY + textContainerOrigin.y, width: 1, height: b.height)
            }
        }
        return nil
    }

    func lineRect(_ line: Int) -> NSRect? {
        guard let tlm = textLayoutManager, let tcm = tlm.textContentManager,
              let r = lineIndex.range(ofLine: line),
              let loc = tcm.location(tcm.documentRange.location, offsetBy: r.location),
              let frag = tlm.textLayoutFragment(for: loc) else { return nil }
        var f = frag.layoutFragmentFrame
        f.origin.y += textContainerOrigin.y
        f.origin.x = 0
        f.size.width = bounds.width
        return f
    }

    var pageGuideColumn: Int? { didSet { needsDisplay = true } }

    override func insertTab(_ sender: Any?) {
        if owner?.typeTab(backward: false) == true { return }
        insertText(Preferences.shared.indentUnit, replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        if owner?.typeTab(backward: true) == true { return }
        super.insertBacktab(sender)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawEditorGuides(in: rect)
        if let col = pageGuideColumn {
            let w = ("0" as NSString).size(withAttributes: [.font: Theme.font]).width
            let x = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0) + w * CGFloat(col)
            NSColor.separatorColor.withAlphaComponent(0.08).setFill()
            NSRect(x: x, y: rect.minY, width: bounds.width - x, height: rect.height).fill()
            NSColor.tertiaryLabelColor.setFill()
            NSRect(x: x, y: rect.minY, width: 1, height: rect.height).fill()
        }
        for line in foldedStartLines {
            guard let r = lineIndex.range(ofLine: line), let end = segmentRects(NSRange(location: NSMaxRange(r), length: 0)).first
                ?? segmentRects(NSRange(location: max(r.location, NSMaxRange(r) - 1), length: 1)).first else { continue }
            let token = NSRect(x: end.maxX + 6, y: end.minY + 1, width: 26, height: max(end.height - 2, 12))
            NSColor.systemYellow.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: token, xRadius: 4, yRadius: 4).fill()
            let dots = NSAttributedString(string: "⋯", attributes: [.font: Theme.font, .foregroundColor: NSColor.secondaryLabelColor])
            dots.draw(at: NSPoint(x: token.midX - dots.size().width / 2, y: token.midY - dots.size().height / 2))
        }
        let sel = selectedRange()
        for p in Placeholders.ranges(in: string) {
            let inner = NSRange(location: p.location + 2, length: p.length - 4)
            (p == sel ? Theme.placeholderSelectedFill : Theme.placeholderFill).setFill()
            for r in segmentRects(inner) where r.intersects(rect) {
                NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: 0.5), xRadius: 5, yRadius: 5).fill()
            }
        }
        for m in findMatches {
            let isCurrent = m == currentFindMatch
            (isCurrent ? NSColor.systemYellow : NSColor.systemYellow.withAlphaComponent(0.3)).setFill()
            for r in segmentRects(m) where r.intersects(rect) {
                NSBezierPath(roundedRect: r.insetBy(dx: -1, dy: 0), xRadius: 2, yRadius: 2).fill()
            }
        }
        if let l = caretLine, l != highlightedLine, var r = lineRect(l), r.intersects(rect) {
            Theme.currentLineBandColor.setFill()
            r.size.width = owner?.textContainerEnd ?? r.width
            r.size.height = Theme.lineHeight
            let radius = CGFloat(EditorMetrics.currentLineBandRadius)
            let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
            p.append(NSBezierPath(rect: NSRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height)))
            p.windingRule = .nonZero
            p.fill()
        }
        if let l = highlightedLine, let r = lineRect(l) {
            Theme.currentLineColor.setFill()
            r.fill()
            if let a = stopAnnotation { drawStopAnnotation(a, in: r) }
        }
        drawDisplayExtras(in: rect)
        drawReviewMarks(in: rect)
        drawMultipleRanges(in: rect)
        drawIssueAnnotations(in: rect)
    }
}

@MainActor
final class JumpBar: NSView {
    static let bandHeight = CGFloat(WorkspaceChrome.jumpBarBandHeight)
    static let separatorHeight = CGFloat(EditorMetrics.jumpBarSeparator)
    static let height: CGFloat = bandHeight + separatorHeight
    let stack = NSStackView()
    let issueStack = NSStackView()
    var onToggleMinimap: (() -> Void)?
    let paneState = JumpBarPaneState()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for s in [stack, issueStack] {
            s.orientation = .horizontal
            s.spacing = 2
            s.translatesAutoresizingMaskIntoConstraints = false
            addSubview(s)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: Self.pathRaise),
            {
                let c = stack.trailingAnchor.constraint(lessThanOrEqualTo: issueStack.leadingAnchor, constant: -6)
                c.priority = .defaultLow
                return c
            }(),
            issueStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            issueStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        issueStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let band = NSRect(x: 0, y: Self.separatorHeight, width: bounds.width, height: bounds.height - Self.separatorHeight)
        if !EditorBlurVeil.applies {
            EditorVeil.fill.setFill()
            band.fill(using: .copy)
        }
        EditorVeil.drawSeparator(NSRect(x: 0, y: 0, width: bounds.width, height: Self.separatorHeight))
    }

    var onRelatedItems: (() -> Void)?
    var onClose: (() -> Void)?
    var showsCloseButton = false { didSet { if oldValue != showsCloseButton { setPath(lastComponents) } } }
    private(set) var closeButton: NSButton?
    private(set) var relatedItemsButton: NSButton?
    var counterparts: [(String, String)] = []
    var onPickCounterpart: ((String) -> Void)?
    private(set) var counterpartsMenu: NSPopUpButton?
    var modes: [String] = []
    var disabledModes: Set<String> = []
    var selectedMode = ""
    var onPickMode: ((String) -> Void)?
    private(set) var modeMenu: NSPopUpButton?
    var relatedTitle = "Counterparts"
    private(set) var lastComponents: [(String, String)] = []
    var symbolTitle: String? { didSet { if oldValue != symbolTitle { setPath(lastComponents) } } }

    func setCounterparts(_ list: [(String, String)]) {
        counterparts = list
        setPath(lastComponents)
    }

    func setPath(_ components: [(String, String)]) {
        lastComponents = components
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        closeButton = nil
        relatedItemsButton = nil
        if showsPaneCloseButton, !showsCloseButton { addPaneCloseButton() }
        if showsCloseButton {
            let b = iconButton("xmark", "Close this Editor Pane")
            b.target = self
            b.action = #selector(closeClicked)
            closeButton = b
            stack.addArrangedSubview(b)
        } else {
            let b = iconButton("square.grid.2x2", "Navigate to Related Items")
            b.setAccessibilityLabel("Related Items")
            b.target = self
            b.action = #selector(relatedItemsClicked)
            relatedItemsButton = b
            stack.addArrangedSubview(b)
        }
        if showsPaneCloseButton { addPaneDivider() }
        counterpartsMenu = nil
        modeMenu = nil
        if !modes.isEmpty {
            let pop = NSPopUpButton(frame: .zero, pullsDown: false)
            pop.addItems(withTitles: modes)
            pop.autoenablesItems = false
            for item in pop.itemArray where disabledModes.contains(item.title) { item.isEnabled = false }
            pop.selectItem(withTitle: selectedMode)
            pop.isBordered = false
            pop.font = .systemFont(ofSize: 11)
            pop.controlSize = .small
            pop.target = self
            pop.action = #selector(modeChosen(_:))
            modeMenu = pop
            stack.addArrangedSubview(pop)
        }
        if !counterparts.isEmpty && !modes.isEmpty {
            let pop = NSPopUpButton(frame: .zero, pullsDown: true)
            pop.addItem(withTitle: relatedTitle)
            for (title, path) in counterparts {
                pop.addItem(withTitle: title)
                pop.lastItem?.representedObject = path
            }
            pop.isBordered = false
            pop.font = .systemFont(ofSize: 11)
            pop.controlSize = .small
            pop.target = self
            pop.action = #selector(counterpartChosen(_:))
            counterpartsMenu = pop
            stack.addArrangedSubview(pop)
        }
        if components.isEmpty { stack.addArrangedSubview(label("No Selection", secondary: true)) }
        for (i, (title, symbol)) in components.enumerated() {
            if i > 0 { stack.addArrangedSubview(chevronLabel()) }
            if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let iv = NSImageView(image: img)
                iv.contentTintColor = pathIconTint(symbol: symbol, title: title)
                stack.addArrangedSubview(iv)
            }
            stack.addArrangedSubview(pathLabel(title, middle: i > 0 && i < components.count - 1))
        }
        if let symbolTitle, !components.isEmpty {
            stack.addArrangedSubview(chevronLabel())
            stack.addArrangedSubview(label(symbolTitle, secondary: symbolTitle == "No Selection"))
        }
    }

    func label(_ s: String, secondary: Bool) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: 11)
        l.textColor = secondary ? .tertiaryLabelColor : pathTextColor
        return l
    }

    @objc private func modeChosen(_ p: NSPopUpButton) { if let t = p.titleOfSelectedItem { onPickMode?(t) } }
    @objc private func relatedItemsClicked() { onRelatedItems?() }
    @objc func closeClicked() { onClose?() }

    var componentTitles: [String] {
        (stack.arrangedSubviews + issueStack.arrangedSubviews).compactMap { v -> String? in
            switch v {
            case let p as NSPopUpButton:
                p.pullsDown ? (p.itemArray.first?.title.isEmpty == false ? p.itemArray.first!.title : (p.accessibilityLabel() ?? ""))
                    : (p.titleOfSelectedItem ?? "")
            case let b as NSButton: b.toolTip ?? b.title
            case let t as NSTextField: t.stringValue
            default: nil
            }
        }
    }

    struct IssueEntry: Equatable { var message: String; var line: Int; var isError: Bool }
    private(set) var issues: [IssueEntry]?
    var onPreviousIssue: (() -> Void)?
    var onNextIssue: (() -> Void)?
    var onPickIssue: ((Int) -> Void)?
    private(set) var issuesMenu: NSPopUpButton?
    private(set) var issueGlyph: String?

    func setIssues(_ list: [IssueEntry]?) {
        guard list != issues || (list != nil && issueStack.arrangedSubviews.isEmpty) else { return }
        issues = list
        issueStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        issuesMenu = nil
        guard let list else { return }
        let prev = iconButton("chevron.left", "Show Previous Issue")
        prev.target = self
        prev.action = #selector(previousIssueClicked)
        let next = iconButton("chevron.right", "Show Next Issue")
        next.target = self
        next.action = #selector(nextIssueClicked)
        let pop = NSPopUpButton(frame: .zero, pullsDown: true)
        pop.isBordered = false
        pop.controlSize = .small
        pop.font = .systemFont(ofSize: 11)
        pop.addItem(withTitle: "")
        let hasError = list.contains { $0.isError }
        issueGlyph = hasError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        pop.item(at: 0)?.image = NSImage(systemSymbolName: issueGlyph!, accessibilityDescription: "Issues")
        pop.imagePosition = .imageOnly
        (pop.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        pop.widthAnchor.constraint(equalToConstant: 20).isActive = true
        pop.toolTip = "Issues"
        pop.setAccessibilityLabel("Issues")
        pop.setAccessibilityTitle("Issues")
        if list.isEmpty {
            pop.addItem(withTitle: "No Issues")
            pop.lastItem?.isEnabled = false
        }
        for e in list {
            let item = NSMenuItem(title: e.message, action: #selector(issuePicked(_:)), keyEquivalent: "")
            item.target = self
            item.tag = e.line
            item.image = NSImage(systemSymbolName: e.isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill", accessibilityDescription: nil)
            pop.menu?.addItem(item)
        }
        issuesMenu = pop
        for v in [prev, pop, next] as [NSView] { issueStack.addArrangedSubview(v) }
    }

    @objc private func previousIssueClicked() { onPreviousIssue?() }
    @objc private func nextIssueClicked() { onNextIssue?() }
    @objc private func issuePicked(_ item: NSMenuItem) { onPickIssue?(item.tag) }
    @objc private func counterpartChosen(_ p: NSPopUpButton) {
        if let path = p.selectedItem?.representedObject as? String { onPickCounterpart?(path) }
    }

    func iconButton(_ symbol: String, _ name: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: name) ?? NSImage(), target: nil, action: nil)
        b.identifier = NSUserInterfaceItemIdentifier(symbol)
        b.isBordered = false
        b.toolTip = name
        return b
    }
}

@MainActor
public final class SourceEditorController: NSViewController, NSTextViewDelegate, NSTextContentManagerDelegate {
    public private(set) var fileURL: URL?
    public var pathComponents: [(String, String)] = [] { didSet { jumpBar.setPath(pathComponents) } }
    public var onBreakpointClick: ((String, Int) -> Void)?
    private var prefsObserver: NSObjectProtocol?
    private var scrollerStyleObserver: NSObjectProtocol?
    private var showsMinimapCache = false
    public var history = NavigationHistory()
    public var onActivate: (() -> Void)?
    public var onRelatedItems: (() -> Void)? { didSet { jumpBar.onRelatedItems = onRelatedItems } }
    public var onClosePane: (() -> Void)? { didSet { jumpBar.onClose = onClosePane } }
    public var showsCloseButton: Bool {
        get { jumpBar.showsCloseButton }
        set { jumpBar.showsCloseButton = newValue }
    }
    public var onPreviousIssue: (() -> Void)? { didSet { jumpBar.onPreviousIssue = onPreviousIssue } }
    public var onNextIssue: (() -> Void)? { didSet { jumpBar.onNextIssue = onNextIssue } }
    public var onPickIssue: ((Int) -> Void)? { didSet { jumpBar.onPickIssue = onPickIssue } }
    public var jumpBarTitles: [String] { jumpBar.componentTitles }
    public var jumpBarIssueTitles: [String]? { jumpBar.issuesMenu.map { $0.itemArray.dropFirst().map(\.title) } }
    public var jumpBarIssueGlyph: (symbol: String, title: String)? {
        jumpBar.issuesMenu.map { (jumpBar.issueGlyph ?? "", $0.itemArray.first?.title ?? "") }
    }
    public var jumpBarIssueArrowSymbols: [String] {
        jumpBar.issueStack.arrangedSubviews.compactMap { v in
            guard let b = v as? NSButton, !(b is NSPopUpButton) else { return nil }
            return b.identifier?.rawValue
        }
    }
    public func setJumpBarIssues(_ list: [(message: String, line: Int, isError: Bool)]?) {
        jumpBar.setIssues(list?.map { JumpBar.IssueEntry(message: $0.message, line: $0.line, isError: $0.isError) })
    }
    public func setCounterparts(_ list: [(String, String)], onPick: @escaping (String) -> Void) {
        jumpBar.onPickCounterpart = onPick
        jumpBar.setCounterparts(list)
    }
    public var counterpartTitles: [String] { jumpBar.counterparts.map(\.0) }

    public func setAssistantModes(_ titles: [String], selected: String, disabled: Set<String> = [], onPick: @escaping (String) -> Void) {
        jumpBar.disabledModes = disabled
        jumpBar.modes = titles
        jumpBar.selectedMode = selected
        jumpBar.relatedTitle = titles.isEmpty ? "Counterparts" : selected
        jumpBar.onPickMode = onPick
        jumpBar.setCounterparts(jumpBar.counterparts)
    }
    public var assistantModeTitles: [String] { jumpBar.modes }
    public var disabledAssistantModes: Set<String> { jumpBar.disabledModes }
    public var onBreakpointMove: ((String, Int, Int) -> Void)?
    public var onBreakpointRemove: ((String, Int) -> Void)?
    public var onBreakpointEdit: ((String, Int) -> Void)?
    public var onRunTest: ((String, Int) -> Void)?
    public var onQuickHelp: ((URL, Position, NSRect) -> Void)?
    public var onJumpToDefinition: ((URL, Position) -> Void)?
    public var onSelectionChange: ((URL, Position) -> Void)?
    public private(set) var isDirty = false
    public var onDocumentOpened: ((URL, String) -> Void)?
    public var onDocumentClosed: ((URL) -> Void)?
    public var onDocumentChanged: ((URL, String) -> Void)?
    public var completionProvider: ((URL, Position) async -> [CompletionItem])?
    let predictionState = PredictionState()
    public var onPredictionStatus: ((PredictionSession.Status) -> Void)?
    public var predictionOtherFiles: (() -> [(path: String, text: String)])?
    public var predictionPath: ((URL) -> String)?
    let completionPopup = CompletionPopupView(frame: NSRect(x: 0, y: 0, width: 380, height: 160))
    public var isShowingCompletions: Bool { completionPopup.superview != nil }
    public var completions: CompletionModel { completionPopup.model }

    let jumpBar = JumpBar()
    let review = CodeReviewState()
    let emptyHolder = EmptyStateHolder()
    public var onBecameEmpty: (() -> Void)?
    public var onContentMovedUnderBars: (() -> Void)?
    final class SymbolCache {
        var symbols: [SymbolScanner.Symbol]?
        var highlightTimer: Timer?
        var highlighted: String?
    }
    let symbolCache = SymbolCache()
    let findBar = FindBarView()
    public let comparison = ComparisonView()
    public var isShowingComparison: Bool { !comparison.isHidden }
    private var findBarHeight: NSLayoutConstraint!
    public private(set) var find = EditorFind()
    public private(set) var foldRegions: [FoldRegion] = []
    public internal(set) var foldedStarts: Set<Int> = []
    public private(set) var hiddenLines: Set<Int> = []
    public var isShowingFindBar: Bool { findBarHeight.constant > 0 }
    let scrollView: NSScrollView = EditorScrollView()
    let textView: SourceTextView
    let gutter: GutterView
    let minimap = MinimapView()
    private var minimapWidth: NSLayoutConstraint!
    var minimapTrailing: NSLayoutConstraint!
    let bandBackdrop = EditorBandBackdrop()
    let stickyHeader = ScopeHeaderView()
    var stickyHeaderTrailing: NSLayoutConstraint!
    var stickyHeaderHeight: NSLayoutConstraint!
    var language = SourceTokenizer.Language.plain
    var displayLanguage: SourceTokenizer.Language { language }
    public internal(set) var syntaxOverride: SourceTokenizer.Language?
    public internal(set) var commentRegions: [FoldRegion] = []
    public var changeBaselines: ((URL) async -> (index: String?, head: String?)?)?
    var changeRefresh: Timer?
    var changeBaselineCache: (url: URL, base: (index: String?, head: String?)?)?
    public internal(set) var changeBaselineLoading: Task<Void, Never>?
    var changeBaselineGeneration = 0
    public var blameLoader: ((URL, String?) async -> [GitBlame.Commit]?)?
    public internal(set) var blameLoading: Task<Void, Never>?
    var blameGeneration = 0
    public static var changeRefreshDelay: TimeInterval = 0.5

    public override init(nibName: NSNib.Name?, bundle: Bundle?) {
        textView = SourceTextView(usingTextLayoutManager: true)
        gutter = GutterView(textView: textView, scrollView: scrollView)
        super.init(nibName: nil, bundle: nil)
    }

    public convenience init() { self.init(nibName: nil, bundle: nil) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let root = NSView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = Theme.font
        textView.textContainerInset = NSSize(width: 0, height: EditorMetrics.firstLineInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = self
        textView.owner = self
        completionPopup.onAccept = { [weak self] in self?.acceptCompletion() }
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = EditorScrollerStyle.initial
        EditorScrollerStyle.follow(scrollView)
        scrollView.drawsBackground = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.clipsToBounds = true
        gutter.clipsToBounds = true
        gutter.onClick = { [weak self] l in self?.fileURL.map { self?.onBreakpointClick?($0.path, l) } }
        gutter.onMove = { [weak self] a, b in self?.fileURL.map { self?.onBreakpointMove?($0.path, a, b) } }
        gutter.onRemove = { [weak self] l in self?.fileURL.map { self?.onBreakpointRemove?($0.path, l) } }
        gutter.onRibbonClick = { [weak self] l in self?.toggleFold(at: l) }
        gutter.onEdit = { [weak self] l in self?.fileURL.map { self?.onBreakpointEdit?($0.path, l) } }
        gutter.onRunTest = { [weak self] l in self?.fileURL.map { self?.onRunTest?($0.path, l) } }
        textView.textLayoutManager?.textContentManager?.delegate = self
        textView.textLayoutManager?.delegate = self

        findBar.onChange = { [weak self] in self?.findChanged() }
        findBar.onStep = { [weak self] f in self?.findStep(forward: f) }
        findBar.onReplace = { [weak self] all in all ? self?.replaceAll() : self?.replaceCurrent() }
        findBar.onDone = { [weak self] in self?.hideFindBar() }
        findBar.clipsToBounds = true
        comparison.isHidden = true
        findBar.wantsLayer = true
        for v in [scrollView, minimap, stickyHeader, bandBackdrop, jumpBar, findBar, comparison] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        stickyHeader.isHidden = true
        bandBackdrop.sources = { [weak self] in self.map { [$0.scrollView, $0.minimap] } ?? [] }
        minimap.onScrollTo = { [weak self] y in self?.scrollMinimapTarget(y) }
        minimap.scrollTarget = scrollView
        stickyHeader.scrollTarget = scrollView
        minimapWidth = minimap.widthAnchor.constraint(equalToConstant: 0)
        minimapTrailing = minimap.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        stickyHeaderTrailing = stickyHeader.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        stickyHeaderHeight = stickyHeader.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            jumpBar.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            jumpBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            jumpBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            jumpBar.heightAnchor.constraint(equalToConstant: JumpBar.height),
            bandBackdrop.topAnchor.constraint(equalTo: root.topAnchor),
            bandBackdrop.bottomAnchor.constraint(equalTo: jumpBar.bottomAnchor),
            bandBackdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bandBackdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            findBar.topAnchor.constraint(equalTo: jumpBar.bottomAnchor),
            findBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stickyHeader.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            stickyHeader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stickyHeaderTrailing, stickyHeaderHeight,
            minimap.topAnchor.constraint(equalTo: root.topAnchor),
            comparison.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            comparison.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            comparison.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            comparison.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            minimap.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            minimapTrailing,
            minimapWidth,
        ])
        findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        findBarHeight.isActive = true
        view = root
        prefsObserver = NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
        scrollerStyleObserver = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                                                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scrollView.scrollerStyle = NSScroller.preferredScrollerStyle
                self?.view.needsLayout = true
            }
        }
        applyPreferences()
        setUpPrediction()
        jumpBar.setPath(pathComponents)
        if fileURL == nil && auxiliary == nil && textView.string.isEmpty { showsNoDocument = true }
    }

    public internal(set) var showsNoDocument: Bool {
        get { noDocument.value }
        set {
            noDocument.value = newValue
            scrollView.rulersVisible = !newValue
            if newValue { textView.isEditable = false }
            minimap.isHidden = newValue || auxiliary != nil || !comparison.isHidden
            scrollView.hasVerticalScroller = !newValue
            if isViewLoaded { view.needsLayout = true }
        }
    }
    let noDocument = NoDocumentFlag()

    public override func viewDidLayout() {
        super.viewDidLayout()
        bandBackdrop.jumpBarTop = view.safeAreaInsets.top
        if minimapWidth.constant > 0 {
            let w = MinimapView.width(forEditorWidth: view.bounds.width)
            if minimapWidth.constant != w { minimapWidth.constant = w }
        }
        updateEditorInsets()
    }

    public var minimapWidthValue: CGFloat { minimapWidth.constant }

    public private(set) var auxiliary: NSView?
    public private(set) var auxiliaryFile: URL?

    public func showAuxiliary(_ v: NSView, path: [(String, String)], file: URL? = nil) {
        _ = view
        try? save()
        hideComparison()
        hideEmptyState()
        auxiliary?.removeFromSuperview()
        auxiliary = v
        v.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(v, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: jumpBar.bottomAnchor), v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor), v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        fileURL = nil
        auxiliaryFile = file
        pathComponents = path
        scrollView.isHidden = true
        minimap.isHidden = true
        stickyHeader.isHidden = true
    }

    public func hideAuxiliary() {
        auxiliary?.removeFromSuperview()
        auxiliary = nil
        auxiliaryFile = nil
        scrollView.isHidden = false
        minimap.isHidden = showsNoDocument
    }

    public func showComparison(old: String, oldTitle: String) {
        _ = view
        comparison.show(old: old, new: textView.string, oldTitle: oldTitle,
                        newTitle: (fileURL?.lastPathComponent ?? "") + " (Local)")
        comparison.isHidden = false
        scrollView.isHidden = true
        minimap.isHidden = true
    }

    public func hideComparison() {
        if !review.inlineShown { removeReviewBar() }
        comparison.onWorkingCopyEdit = nil
        comparison.isHidden = true
        scrollView.isHidden = false
        minimap.isHidden = showsNoDocument
    }

    @discardableResult
    public func performFind(tag: Int) -> Bool {
        switch tag {
        case 1: showFindBar(replace: false)
        case 12: showFindBar(replace: true)
        case 2: findStep(forward: true)
        case 3: findStep(forward: false)
        case 7: useSelectionForFind()
        case 4: replaceAll()
        case 5, 6: replaceCurrent()
        case 9, 10: selectFindMatches(inSelectionOnly: tag == 10)
        default: return false
        }
        return true
    }

    public func selectFindMatches(inSelectionOnly: Bool) {
        if find.matches.isEmpty { findChanged() }
        let sel = textView.selectedRange()
        let ms = inSelectionOnly ? find.matches.filter { NSIntersectionRange($0, sel).length == $0.length && $0.length > 0 } : find.matches
        guard !ms.isEmpty else { NSSound.beep(); return }
        textView.setSelectedRanges(ms.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
    }

    public func showFindBar(replace: Bool) {
        _ = view
        findBar.replaceRow.isHidden = !replace
        findBarHeight.constant = replace ? 60 : 32
        view.window?.makeFirstResponder(findBar.queryField)
        findChanged()
    }

    public func hideFindBar() {
        findBarHeight.constant = 0
        textView.findMatches = []
        textView.currentFindMatch = nil
        view.window?.makeFirstResponder(textView)
    }

    public func setFind(_ query: String, replacement: String = "", options: WorkspaceSearch.Options = .init()) {
        _ = view
        findBar.queryField.stringValue = query
        findBar.replaceField.stringValue = replacement
        findBar.style.selectItem(at: options.regularExpression ? 1 : 0)
        findBar.match.selectItem(at: options.wholeWord ? 1 : 0)
        findBar.caseMode.selectItem(at: options.ignoreCase ? 0 : 1)
        findChanged()
    }

    func findChanged() {
        find.query = findBar.queryField.stringValue
        find.replacement = findBar.replaceField.stringValue
        find.options = findBar.options
        find.update(text: textView.string, from: textView.selectedRange().location)
        showFindState(select: false)
    }

    public func findStep(forward: Bool) {
        if find.matches.isEmpty { findChanged() }
        find.step(forward)
        showFindState(select: true)
    }

    private func showFindState(select: Bool) {
        textView.findMatches = find.matches
        textView.currentFindMatch = find.currentRange
        findBar.countLabel.stringValue = find.query.isEmpty ? "" : (find.matches.isEmpty ? "No matches" : "\((find.current ?? 0) + 1) of \(find.matches.count)")
        if select, let r = find.currentRange {
            textView.setSelectedRange(r)
            textView.scrollRangeToVisible(r)
        }
    }

    public func useSelectionForFind() {
        let sel = textView.selectedRange()
        guard sel.length > 0 else { return }
        setFind((textView.string as NSString).substring(with: sel), options: findBar.options)
    }

    public func replaceCurrent() {
        find.replacement = findBar.replaceField.stringValue
        guard let r = find.currentRange else { return }
        let text = find.replacementText(in: textView.string, range: r)
        if textView.shouldChangeText(in: r, replacementString: text) {
            textView.replaceCharacters(in: r, with: text)
            textView.didChangeText()
        }
        find.update(text: textView.string, from: r.location + (text as NSString).length)
        showFindState(select: true)
    }

    public func replaceAll() {
        find.replacement = findBar.replaceField.stringValue
        let (newText, count) = find.replacingAll(in: textView.string)
        guard count > 0 else { return }
        let all = NSRange(location: 0, length: (textView.string as NSString).length)
        if textView.shouldChangeText(in: all, replacementString: newText) {
            textView.replaceCharacters(in: all, with: newText)
            textView.didChangeText()
        }
        find.update(text: textView.string)
        showFindState(select: false)
        findBar.countLabel.stringValue = "Replaced \(count)"
    }

    public func applyPreferences() {
        bandBackdrop.themeChanged()
        jumpBar.needsDisplay = true
        _ = view
        let p = Preferences.shared
        showsLineNumbers = p.showLineNumbers
        gutter.showsRibbon = p.showFoldingRibbon
        showsMinimap = p.showMinimap
        textView.pageGuideColumn = p.showPageGuide ? p.pageGuideColumn : nil
        textView.backgroundColor = Theme.backgroundColor
        textView.insertionPointColor = Theme.textColor
        textView.selectedTextAttributes = [.backgroundColor: Theme.selectionColor]
        textView.typingAttributes = [.font: Theme.font, .foregroundColor: Theme.textColor]
        let tab = Theme.advance * CGFloat(p.tabWidth)
        let para = NSMutableParagraphStyle()
        para.defaultTabInterval = tab
        para.tabStops = []
        para.minimumLineHeight = Theme.lineHeight
        para.maximumLineHeight = Theme.lineHeight
        wrapSnapshot = WrapSnapshot(wraps: p.wrapLines && p.wrappedLineIndent > 0, advance: Theme.advance, tabWidth: p.tabWidth)
        if let ts = textView.textStorage, ts.length > 0 {
            ts.addAttribute(.paragraphStyle, value: para.copy(), range: NSRange(location: 0, length: ts.length))
        }
        textView.defaultParagraphStyle = para
        textView.isHorizontallyResizable = !p.wrapLines
        textView.textContainer?.widthTracksTextView = p.wrapLines
        if !p.wrapLines {
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        } else {
            scrollView.hasHorizontalScroller = false
            textView.frame.size.width = scrollView.contentSize.width
            updateTextContainerWidth()
        }
        scrollView.scrollerStyle = EditorScrollerStyle.initial
        recolorAll()
        updateMinimapRows()
        textView.textStorage?.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: textView.textStorage!.length))
        applyDisplayPreferences()
        applyPredictionPreferences()
        textView.needsDisplay = true
        gutter.needsDisplay = true
    }

    public func trimTrailingWhitespace() {
        let ns = textView.string as NSString
        guard let re = try? NSRegularExpression(pattern: "[ \\t]+$", options: .anchorsMatchLines) else { return }
        let trimBlank = Preferences.shared.trimWhitespaceOnlyLines
        let matches = re.matches(in: textView.string, range: NSRange(location: 0, length: ns.length)).filter { m in
            trimBlank || ns.lineRange(for: NSRange(location: m.range.location, length: 0)).location != m.range.location
        }
        guard !matches.isEmpty else { return }
        textView.undoManager?.beginUndoGrouping()
        for m in matches.reversed() where textView.shouldChangeText(in: m.range, replacementString: "") {
            textView.replaceCharacters(in: m.range, with: "")
            textView.didChangeText()
        }
        textView.undoManager?.endUndoGrouping()
    }

    public var pageGuideColumn: Int? { textView.pageGuideColumn }
    public var wrapsLines: Bool { textView.textContainer?.widthTracksTextView ?? true }

    public func applyTextEdits(_ edits: [TextEdit]) {
        _ = view
        let index = textView.lineIndex
        let sorted = edits.sorted {
            if $0.start.line != $1.start.line { return $0.start.line > $1.start.line }
            return $0.start.character > $1.start.character
        }
        textView.undoManager?.beginUndoGrouping()
        for e in sorted {
            let a = index.offset(of: e.start), b = index.offset(of: e.end)
            let r = NSRange(location: a, length: max(0, b - a))
            if textView.shouldChangeText(in: r, replacementString: e.newText) {
                textView.replaceCharacters(in: r, with: e.newText)
                textView.didChangeText()
            }
        }
        textView.undoManager?.endUndoGrouping()
        textView.undoManager?.setActionName("Refactor")
    }

    public func highlightOccurrences(of name: String?) {
        _ = view
        guard let name, !name.isEmpty else { textView.findMatches = []; textView.currentFindMatch = nil; return }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
        let re = try? NSRegularExpression(pattern: pattern)
        textView.findMatches = re?.matches(in: textView.string, range: NSRange(location: 0, length: (textView.string as NSString).length)).map(\.range) ?? []
        textView.currentFindMatch = nil
    }

    public var highlightedOccurrences: [NSRange] { textView.findMatches }

    func showRenameField(name: String, at range: NSRange, onCommit: @escaping (String) -> Void) {
        let rect = textView.segmentRects(range).first ?? .zero
        let field = RenameField(string: name)
        field.frame = NSRect(x: rect.minX - 2, y: rect.minY - 2, width: max(120, rect.width + 40), height: rect.height + 4)
        field.font = Theme.font
        field.onCommit = { [weak field, weak self] text in
            field?.removeFromSuperview()
            self?.view.window?.makeFirstResponder(self?.textView)
            if let text { onCommit(text) } else { self?.highlightOccurrences(of: nil) }
        }
        field.onChange = { [weak self] text in self?.highlightOccurrences(of: name); _ = text }
        textView.addSubview(field)
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @discardableResult
    public func insertLibraryText(_ text: String) -> Bool {
        _ = view
        guard fileURL != nil, textView.isEditable else { return false }
        let at = textView.selectedRange()
        textView.insertText(text, replacementRange: at)
        selectFirstPlaceholder(inInserted: NSRange(location: at.location, length: (text as NSString).length))
        return true
    }

    public func open(_ url: URL) throws {
        _ = view
        dismissPrediction()
        hideComparison()
        hideInlineComparison()
        hideAuxiliary()
        hideEmptyState()
        let text = try String(contentsOf: url, encoding: .utf8)
        let old = fileURL
        fileURL = url
        if let old, old != url { onDocumentClosed?(old) }
        textView.isEditable = true
        syntaxOverride = nil
        language = .init(fileName: url.lastPathComponent)
        symbolCache.symbols = nil
        clearMultipleSelection()
        showsNoDocument = false
        textView.string = text
        isDirty = false
        reindex()
        resetSyntax()
        updateMinimapRows()
        updateDisplayExtras()
        refreshSourceChanges()
        onDocumentOpened?(url, text)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: textView))
        contentMovedUnderBars()
    }

    public func closeFile() {
        _ = view
        dismissPrediction()
        let old = fileURL
        showText("", title: "")
        pathComponents = []
        jumpBar.symbolTitle = nil
        textView.caretLine = nil
        gutter.caretLine = nil
        showsNoDocument = true
        if let old { onDocumentClosed?(old) }
        onBecameEmpty?()
    }

    public func showText(_ text: String, title: String) {
        _ = view
        try? save()
        fileURL = nil
        language = .plain
        syntaxOverride = nil
        symbolCache.symbols = nil
        clearMultipleSelection()
        showsNoDocument = false
        textView.string = text
        textView.isEditable = false
        refreshSourceChanges()
        isDirty = false
        reindex()
        resetSyntax()
        pathComponents = [(title, "doc.plaintext")]
        setIssues([])
        setBreakpoints([:], active: true)
        setCurrentLine(nil)
    }

    public func save() throws {
        guard let url = fileURL, isDirty else { return }
        if Preferences.shared.convertExistingFilesOnSave { convertLineEndings() }
        if Preferences.shared.trimTrailingWhitespace { trimTrailingWhitespace() }
        try textView.string.write(to: url, atomically: true, encoding: .utf8)
        isDirty = false
        refreshSourceChanges()
        onSave?(url)
    }

    public var onSave: ((URL) -> Void)?

    public var text: String { textView.string }

    public static var incrementalEditing = true
    public static var lazyThreshold = 3_000
    private var pendingEdit: (range: NSRange, newLength: Int, oldText: String)?
    private var deferredIndex: DispatchWorkItem?
    public internal(set) var lastHighlightWasIncremental = false
    let syntax = EditorSyntaxState()

    func noteEdit(range: NSRange, replacement: String) {
        if !textView.issues.isEmpty { textView.issuesStale = true; gutter.marks.issuesStale = true }
        let ns = textView.string as NSString
        let old = NSMaxRange(range) <= ns.length ? ns.substring(with: range) : ""
        pendingEdit = pendingEdit == nil ? (range, (replacement as NSString).length, old) : (NSRange(location: 0, length: 0), -1, "")
    }

    public func textDidChange(_ notification: Notification) {
        symbolCache.symbols = nil
        isDirty = true
        reindex()
        rehighlight()
        updateDisplayExtras()
        refreshInlineComparison()
        scheduleSourceChangesRefresh()
        contentMovedUnderBars()
        if let url = fileURL { onDocumentChanged?(url, textView.string) }
        let caret = textView.selectedRange().location
        let ns = textView.string as NSString
        if isShowingCompletions {
            let start = completionPopup.model.wordStart
            if caret < start { hideCompletions() } else {
                var m = completionPopup.model
                m.filter(ns.substring(with: NSRange(location: start, length: caret - start)))
                showCompletions(m)
            }
        } else if caret > 0, ns.character(at: caret - 1) == 46 , language == .swift {
            requestCompletion()
        }
        predictionTextDidChange()
    }

    public var caretPosition: Position { textView.lineIndex.position(at: textView.selectedRange().location) }

    public func requestCompletion() {
        guard let url = fileURL, let provider = completionProvider else { return }
        let caret = textView.selectedRange().location
        let ns = textView.string as NSString
        let start = CompletionModel.wordStart(in: ns, before: caret)
        let prefix = ns.substring(with: NSRange(location: start, length: caret - start))
        let pos = textView.lineIndex.position(at: caret)
        Task {
            let items = await provider(url, pos)
            guard self.textView.selectedRange().location == caret, !items.isEmpty else { return }
            var m = CompletionModel()
            m.reset(items: items, wordStart: start, prefix: prefix)
            self.showCompletions(m)
        }
    }

    public func showCompletions(_ m: CompletionModel) {
        dismissPrediction()
        completionPopup.model = m
        guard !m.visible.isEmpty else { return hideCompletions() }
        let anchor = textView.caretRect(at: m.wordStart) ?? NSRect(x: 40, y: 20, width: 0, height: 16)
        let labelInset: CGFloat = 8 + ("M  " as NSString).size(withAttributes: [.font: Theme.boldFont]).width
        let height = CompletionPopupView.height(rows: m.visible.count, hasDoc: completionPopup.hasDoc)
        let inText = NSRect(x: max(0, anchor.minX - labelInset), y: anchor.maxY + 2, width: 380, height: height)
        completionPopup.frame = view.convert(inText, from: textView)
        if completionPopup.superview == nil { view.addSubview(completionPopup, positioned: .above, relativeTo: nil) }
    }

    public func hideCompletions() { completionPopup.removeFromSuperview() }

    public var completionFrameInText: NSRect { textView.convert(completionPopup.frame, from: view) }

    public func acceptCompletion() {
        guard let item = completionPopup.model.current else { return hideCompletions() }
        let caret = textView.selectedRange().location
        var start = completionPopup.model.wordStart
        if let r = item.replaceStart { start = min(caret, textView.lineIndex.offset(of: r)) }
        let range = NSRange(location: start, length: caret - start)
        hideCompletions()
        let text = item.isSnippet ? Placeholders.fromLSPSnippet(item.insertText) : item.insertText
        if textView.shouldChangeText(in: range, replacementString: text) {
            textView.replaceCharacters(in: range, with: text)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: start + (text as NSString).length, length: 0))
            selectFirstPlaceholder(inInserted: NSRange(location: start, length: (text as NSString).length))
        }
    }

    func handlePlaceholderKey(_ e: NSEvent) -> Bool {
        let flags = e.modifierFlags.intersection([.shift, .command, .option, .control])
        switch e.keyCode {
        case 48 where flags.isEmpty || flags == .shift: return selectPlaceholder(backward: flags == .shift)
        case 36, 76 where flags.isEmpty: return acceptSelectedPlaceholder()
        default: return false
        }
    }

    @discardableResult
    public func selectPlaceholder(backward: Bool = false) -> Bool {
        guard let r = Placeholders.next(from: textView.selectedRange(), in: textView.string, backward: backward) else { return false }
        textView.setSelectedRange(r)
        textView.scrollRangeToVisible(r)
        return true
    }

    @discardableResult
    public func acceptSelectedPlaceholder() -> Bool {
        let sel = textView.selectedRange()
        guard Placeholders.ranges(in: textView.string).contains(sel) else { return false }
        let text = Placeholders.text(of: sel, in: textView.string)
        guard textView.shouldChangeText(in: sel, replacementString: text) else { return false }
        textView.replaceCharacters(in: sel, with: text)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: sel.location + (text as NSString).length, length: 0))
        return true
    }

    func selectFirstPlaceholder(inInserted inserted: NSRange) {
        if let p = Placeholders.ranges(in: textView.string).first(where: { NSIntersectionRange($0, inserted).length == $0.length }) {
            textView.setSelectedRange(p)
        }
    }

    func handleCompletionKey(_ e: NSEvent) -> Bool {
        guard isShowingCompletions else { return false }
        switch e.keyCode {
        case 125, 126:
            var m = completionPopup.model
            m.move(e.keyCode == 125 ? 1 : -1)
            showCompletions(m)
        case 36, 76, 48: acceptCompletion()
        case 53: hideCompletions()
        default: return false
        }
        return true
    }

    public func quickHelp(atOffset offset: Int) {
        guard let url = fileURL else { return }
        let rect = textView.segmentRects(NSRange(location: offset, length: 0)).first ?? .zero
        onQuickHelp?(url, textView.lineIndex.position(at: offset), rect)
    }

    public func jumpToDefinition(atOffset offset: Int) {
        guard let url = fileURL else { return }
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        onJumpToDefinition?(url, textView.lineIndex.position(at: offset))
    }

    public var jumpBarSymbol: String? { jumpBar.symbolTitle }

    var documentSymbols: [SymbolScanner.Symbol] {
        guard fileURL != nil, language.isCode else { return [] }
        if symbolCache.symbols == nil { symbolCache.symbols = SymbolScanner.symbols(in: textView.string, language: language) }
        return symbolCache.symbols ?? []
    }

    func updateSymbolComponent() {
        guard fileURL != nil, language.isCode else { jumpBar.symbolTitle = nil; return }
        if symbolCache.symbols == nil, deferredIndex != nil { return }
        if symbolCache.symbols == nil { symbolCache.symbols = SymbolScanner.symbols(in: textView.string, language: language) }
        let best = DocumentSymbols.enclosing(symbolCache.symbols ?? [], line: currentLine, text: textView.string as NSString, index: textView.lineIndex)
        jumpBar.symbolTitle = best?.name ?? "No Selection"
    }

    func endLine(of s: SymbolScanner.Symbol) -> Int {
        DocumentSymbols.endLine(of: s, text: textView.string as NSString, index: textView.lineIndex)
    }

    public var identifierAtCaret: String? {
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        guard sel.length == 0, ns.length > 0 else { return nil }
        let word = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        func isWord(_ i: Int) -> Bool { i >= 0 && i < ns.length && UnicodeScalar(ns.character(at: i)).map(word.contains) == true }
        var a = sel.location, b = sel.location
        while isWord(a - 1) { a -= 1 }
        while isWord(b) { b += 1 }
        guard b > a else { return nil }
        let w = ns.substring(with: NSRange(location: a, length: b - a))
        return w.first?.isNumber == true ? nil : w
    }

    public var highlightedSymbol: String? { symbolCache.highlighted }

    func scheduleSymbolHighlight() {
        symbolCache.highlightTimer?.invalidate()
        let p = Preferences.shared
        guard p.highlightSelectedSymbol, !isShowingFindBar else { return }
        if symbolCache.highlighted != nil { symbolCache.highlighted = nil; highlightOccurrences(of: nil) }
        guard let name = identifierAtCaret, language.isCode else { return }
        symbolCache.highlightTimer = Timer.scheduledTimer(withTimeInterval: p.highlightDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySymbolHighlight(name) }
        }
    }

    public func applySymbolHighlight(_ name: String) {
        guard identifierAtCaret == name else { return }
        symbolCache.highlighted = name
        highlightOccurrences(of: name)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        if pendingEdit == nil, textView.lineIndex.length != (textView.string as NSString).length {
            let idx = LineIndex(textView.string)
            textView.lineIndex = idx
            gutter.lineIndex = idx
        }
        predictionSelectionDidChange()
        let caret = fileURL == nil && textView.string.isEmpty ? nil : currentLine
        textView.caretLine = caret
        gutter.caretLine = caret
        updateSymbolComponent()
        scheduleSymbolHighlight()
        dropClosersOffCaretLine()
        guard let url = fileURL else { return }
        onSelectionChange?(url, caretPosition)
    }

    public func reveal(position p: Position) {
        let offset = textView.lineIndex.offset(of: p)
        textView.setSelectedRange(NSRange(location: offset, length: 0))
        textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
    }

    public nonisolated func textContentManager(_ textContentManager: NSTextContentManager,
                                               shouldEnumerate textElement: NSTextElement,
                                               options: NSTextContentManager.EnumerationOptions) -> Bool {
        let snap = foldSnapshot
        guard !snap.hidden.isEmpty, let range = textElement.elementRange else { return true }
        let offset = textContentManager.offset(from: textContentManager.documentRange.location, to: range.location)
        return !snap.hidden.contains(snap.index.line(at: offset))
    }

    nonisolated(unsafe) private var foldSnapshot = (hidden: Set<Int>(), index: LineIndex(""))
    nonisolated(unsafe) var wrapSnapshot = WrapSnapshot()

    public var allFoldRegions: [FoldRegion] { foldRegions + commentRegions }

    func applyFolds() {
        let all = allFoldRegions
        hiddenLines = Set(all.filter { foldedStarts.contains($0.startLine) }.flatMap { Array($0.hiddenLines) })
        foldSnapshot = (hiddenLines, textView.lineIndex)
        gutter.foldStarts = Dictionary(all.map { ($0.startLine, foldedStarts.contains($0.startLine)) }, uniquingKeysWith: { a, _ in a })
        textView.foldedStartLines = foldedStarts
        if let tlm = textView.textLayoutManager {
            tlm.invalidateLayout(for: tlm.documentRange)
            tlm.ensureLayout(for: tlm.documentRange)
        }
        textView.needsDisplay = true
        gutter.needsDisplay = true
    }

    public func toggleFold(at line: Int) {
        guard let r = allFoldRegions.first(where: { $0.startLine == line }) ?? FoldRegions.innermost(foldRegions, containing: line) else { return }
        if foldedStarts.contains(r.startLine) { foldedStarts.remove(r.startLine) } else { foldedStarts.insert(r.startLine) }
        applyFolds()
    }

    @objc public func fold(_ sender: Any?) {
        let line = currentLine
        let comment = commentRegions.first { $0.contains(line: line) && !foldedStarts.contains($0.startLine) }
        guard let r = comment ?? foldRegions.filter({ $0.contains(line: line) && !foldedStarts.contains($0.startLine) }).max(by: { $0.depth < $1.depth }) else { return }
        foldedStarts.insert(r.startLine)
        applyFolds()
    }

    @objc public func unfold(_ sender: Any?) {
        let line = currentLine
        foldedStarts = foldedStarts.filter { s in !(allFoldRegions.first { $0.startLine == s }?.contains(line: line) ?? false) }
        applyFolds()
    }

    @objc public func foldAll(_ sender: Any?) {
        foldedStarts = Set(foldRegions.map(\.startLine))
        applyFolds()
    }

    @objc public func unfoldAll(_ sender: Any?) {
        foldedStarts = []
        applyFolds()
    }

    private func reindex() {
        let idx: LineIndex
        let newLength = (textView.string as NSString).length
        if Self.incrementalEditing, let e = pendingEdit, e.newLength >= 0, textView.lineIndex.length + e.newLength - e.range.length == newLength {
            var i = textView.lineIndex
            let ns = textView.string as NSString
            i.applyEdit(range: e.range, replacement: ns.substring(with: NSRange(location: e.range.location, length: e.newLength)))
            idx = i
        } else {
            idx = LineIndex(textView.string)
        }
        textView.lineIndex = idx
        gutter.lineIndex = idx
        if Self.incrementalEditing && idx.starts.count > Self.lazyThreshold && pendingEdit != nil {
            deferredIndex?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reindexDeferred() }
            deferredIndex = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            return
        }
        reindexDeferred()
    }

    func reindexDeferred() {
        deferredIndex = nil
        foldRegions = FoldRegions.regions(in: textView.string, language: language)
        commentRegions = FoldRegions.commentRegions(in: textView.string, language: language)
        foldedStarts = foldedStarts.filter { s in allFoldRegions.contains { $0.startLine == s } }
        updateMinimapRows()
        applyFolds()
        updateSymbolComponent()
        updateScopeGuides()
    }

    public func setBreakpoints(_ lines: [Int: Bool], active: Bool, customized: Set<Int> = []) {
        gutter.marks.breakpoints = lines
        gutter.marks.customized = customized
        gutter.marks.breakpointsActive = active
    }

    public var issuesAreStale: Bool { textView.issuesStale }
    public var showsInlineIssues: Bool {
        get { textView.showsIssues }
        set { textView.showsIssues = newValue }
    }

    public func setIssues(_ issues: [Diagnostic]) {
        let path = fileURL?.standardizedFileURL.path
        let mine = issues.filter { $0.location.map { URL(fileURLWithPath: $0.file).standardizedFileURL.path } == path }
        let grouped = Dictionary(grouping: mine, by: { $0.location!.line })
        if grouped != textView.issues {
            textView.issues = grouped
            textView.issuesStale = false
            gutter.marks.issuesStale = false
        }
        gutter.marks.issues = textView.issues.mapValues { list in list.contains { $0.severity == .error } ? .error : .warning }
        gutter.marks.fixable = Set(textView.issues.filter { $0.value.contains { !$0.fixIts.isEmpty } }.keys)
    }

    public func annotationLine(at p: NSPoint) -> Int? {
        guard textView.showsIssues else { return nil }
        let line = textView.lineIndex.line(at: textView.characterIndexForInsertion(at: p))
        guard textView.issues[line]?.isEmpty == false, let r = textView.lineRect(line), r.contains(p),
              let lr = textView.lineIndex.range(ofLine: line) else { return nil }
        let end = NSMaxRange(lr)
        let textEnd = textView.segmentRects(NSRange(location: max(lr.location, end - 1), length: end > lr.location ? 1 : 0)).first?.maxX ?? r.minX
        return p.x >= textEnd + 16 ? line : nil
    }

    public func fixItMenu(line: Int) -> NSMenu? {
        guard let list = textView.issues[line], list.contains(where: { !$0.fixIts.isEmpty }),
              let first = InlineIssueLayout.primary(list.filter { !$0.fixIts.isEmpty }) else { return nil }
        let m = NSMenu()
        m.autoenablesItems = false
        let title = NSMenuItem(title: first.message, action: nil, keyEquivalent: "")
        title.isEnabled = false
        m.addItem(title)
        let fix = NSMenuItem(title: "Fix", action: #selector(fixItChosen(_:)), keyEquivalent: "")
        fix.target = self
        fix.tag = line
        m.addItem(fix)
        return m
    }

    @objc func fixItChosen(_ item: NSMenuItem) { gutter.onFixIt?(item.tag) }

    public func setTests(_ marks: [Int: GutterView.TestStatusMark]) { gutter.marks.tests = marks }

    public func setCoverage(_ counts: [Int: Int], shown: Bool) {
        gutter.marks.coverage = counts
        gutter.showsCoverage = shown
    }

    public func setStopAnnotation(_ text: String?) { textView.stopAnnotation = text }
    public var stopAnnotationText: String? { textView.stopAnnotation }

    public func setCurrentLine(_ line: Int?) {
        let changed = textView.highlightedLine != line
        textView.highlightedLine = line
        gutter.marks.currentLine = line
        if let line, changed, let r = textView.lineIndex.range(ofLine: line) { textView.scrollRangeToVisible(r) }
    }

    public var currentLine: Int { textView.lineIndex.line(at: textView.selectedRange().location) }

    public func reveal(line: Int) {
        guard let r = textView.lineIndex.range(ofLine: line) else { return }
        textView.setSelectedRange(NSRange(location: r.location, length: 0))
        textView.scrollRangeToVisible(r)
    }

    public var showsMinimap: Bool {
        get { minimapWidth.constant > 0 }
        set {
            _ = view
            minimapWidth.constant = newValue ? MinimapView.width(forEditorWidth: view.bounds.width) : 0
            if newValue != showsMinimapCache {
                showsMinimapCache = newValue
                updateEditorInsets()
                if newValue { updateMinimapRows() }
            }
        }
    }

    public var showsLineNumbers: Bool {
        get { gutter.showsLineNumbers }
        set { gutter.showsLineNumbers = newValue }
    }

    @objc public func toggleMinimap(_ sender: Any?) { Preferences.shared.showMinimap.toggle() }
    @objc public func toggleLineNumbers(_ sender: Any?) { showsLineNumbers.toggle() }

}

final class RenameField: NSTextField, NSTextFieldDelegate {
    var onCommit: ((String?) -> Void)?
    var onChange: ((String) -> Void)?
    override init(frame: NSRect) { super.init(frame: frame); delegate = self }
    convenience init(string: String) { self.init(frame: .zero); stringValue = string }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    func controlTextDidChange(_ obj: Notification) { onChange?(stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.insertNewline(_:)) { onCommit?(stringValue); onCommit = nil; return true }
        if sel == #selector(NSResponder.cancelOperation(_:)) { onCommit?(nil); onCommit = nil; return true }
        return false
    }
}

extension SourceEditorController {
    public func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard fileURL != nil, !menu.items.contains(where: { $0.action == Self.showCodeActionsAction }) else { return menu }
        menu.insertItem(NSMenuItem(title: "Show Code Actions", action: Self.showCodeActionsAction, keyEquivalent: ""), at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    static let showCodeActionsAction = NSSelectorFromString("showCodeActions:")
}

@MainActor final class NoDocumentFlag { var value = false }
