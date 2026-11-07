import AppKit
import YcodeIDECore

@MainActor
public final class CodeReviewState {
    public var style: ComparisonStyle = .inline
    public internal(set) var inlineShown = false
    public internal(set) var changes: [ReviewChange] = []
    public internal(set) var current: Int?
    public internal(set) var leftSource: ReviewSource = .uncommittedChanges
    public internal(set) var rightSource: ReviewSource = .lastCommit
    var baseline = ""
    var leftText: String?
    var host: ((CodeReviewBar?) -> Void)?
    let bar = CodeReviewBar()
}

@MainActor
public final class CodeReviewBar: NSView {
    public let previous = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous Change")!, target: nil, action: nil)
    public let next = NSButton(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next Change")!, target: nil, action: nil)
    public let count = NSTextField(labelWithString: "")
    public let leftSource = NSButton(title: "Uncommitted Changes", target: nil, action: nil)
    public let swap = NSButton(image: NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Swap")!, target: nil, action: nil)
    public let rightSource = NSButton(title: "Last Commit", target: nil, action: nil)
    var onStep: ((Bool) -> Void)?
    var onSwap: (() -> Void)?
    var onPick: ((Bool, NSView) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        count.font = .systemFont(ofSize: 11)
        for b in [previous, next, swap] { b.isBordered = false; b.target = self }
        for b in [leftSource, rightSource] { b.bezelStyle = .inline; b.controlSize = .small; b.target = self }
        previous.action = #selector(prev)
        next.action = #selector(nxt)
        swap.action = #selector(swapped)
        leftSource.action = #selector(pickLeft)
        rightSource.action = #selector(pickRight)
        let stack = NSStackView(views: [previous, count, next, NSBox.separatorView(), leftSource, swap, rightSource])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func prev() { onStep?(false) }
    @objc private func nxt() { onStep?(true) }
    @objc private func swapped() { onSwap?() }
    @objc private func pickLeft() { onPick?(true, leftSource) }
    @objc private func pickRight() { onPick?(false, rightSource) }
}

extension NSBox {
    static func separatorView() -> NSView {
        let b = NSBox()
        b.boxType = .separator
        b.widthAnchor.constraint(equalToConstant: 1).isActive = true
        b.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return b
    }
}

@MainActor
public final class ReviewSourcePicker: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    public let columns: CodeReviewModel.PickerColumns
    public let branchSearch = NSSearchField()
    public let commitSearch = NSSearchField()
    let branchTable = NSTableView()
    let commitTable = NSTableView()
    public private(set) var shownBranches: [String] = []
    public private(set) var shownCommits: [String] = []
    let commitSources: [ReviewSource]
    let branchSources: [String: ReviewSource]
    var onChoose: ((ReviewSource) -> Void)?

    init(columns: CodeReviewModel.PickerColumns, commitSources: [ReviewSource], branchSources: [String: ReviewSource]) {
        self.columns = columns
        self.commitSources = commitSources
        self.branchSources = branchSources
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        func column(_ title: String, _ field: NSSearchField, _ table: NSTableView) -> NSView {
            let heading = NSTextField(labelWithString: title)
            heading.font = .boldSystemFont(ofSize: 11)
            field.delegate = self
            table.addTableColumn(NSTableColumn(identifier: .init("c")))
            table.headerView = nil
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.action = #selector(clicked(_:))
            let scroll = NSScrollView()
            scroll.documentView = table
            scroll.hasVerticalScroller = true
            scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
            let s = NSStackView(views: [heading, field, scroll])
            s.orientation = .vertical
            s.alignment = .leading
            for v in [field, scroll] { v.widthAnchor.constraint(equalTo: s.widthAnchor).isActive = true }
            return s
        }
        let root = NSStackView(views: [column("Branches & Tags", branchSearch, branchTable), column("Commits", commitSearch, commitTable)])
        root.orientation = .horizontal
        root.distribution = .fillEqually
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        root.frame = NSRect(x: 0, y: 0, width: 620, height: 290)
        view = root
        filter()
    }

    func filter() {
        let b = branchSearch.stringValue.lowercased(), c = commitSearch.stringValue.lowercased()
        shownBranches = b.isEmpty ? columns.branches : columns.branches.filter { $0.lowercased().contains(b) }
        shownCommits = c.isEmpty ? columns.commits : columns.commits.filter { $0.lowercased().contains(c) }
        branchTable.reloadData()
        commitTable.reloadData()
    }

    public func controlTextDidChange(_ obj: Notification) { filter() }
    public func numberOfRows(in t: NSTableView) -> Int { t === branchTable ? shownBranches.count : shownCommits.count }
    public func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        let s = t === branchTable ? shownBranches[row] : shownCommits[row]
        let l = NSTextField(labelWithString: s)
        l.lineBreakMode = .byTruncatingTail
        if s == "Recents" { l.font = .boldSystemFont(ofSize: 11); l.textColor = .secondaryLabelColor }
        return l
    }

    @objc func clicked(_ t: NSTableView) {
        guard t.clickedRow >= 0 else { return }
        choose(table: t === branchTable ? 0 : 1, row: t.clickedRow)
    }

    @discardableResult
    public func choose(table: Int, row: Int) -> ReviewSource? {
        var source: ReviewSource?
        if table == 0, shownBranches.indices.contains(row) {
            source = branchSources[shownBranches[row].replacingOccurrences(of: " (current)", with: "")]
        } else if table == 1, shownCommits.indices.contains(row), let i = columns.commits.firstIndex(of: shownCommits[row]) {
            source = commitSources.indices.contains(i) ? commitSources[i] : nil
        }
        if let source { onChoose?(source); if presentingViewController != nil { dismiss(nil) } }
        return source
    }
}

@MainActor
final class RibbonView: NSView {
    var changes: [ReviewChange] = [] { didSet { needsDisplay = true } }
    var leftY: ((Int) -> CGFloat)?
    var rightY: ((Int) -> CGFloat)?
    var lineHeight: CGFloat = 15
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let leftY, let rightY else { return }
        for c in changes {
            let color: NSColor = c.kind == .added ? .systemGreen : (c.kind == .removed ? .systemRed : .systemBlue)
            let l0 = leftY(c.newStart), l1 = l0 + CGFloat(c.newCount) * lineHeight
            let r0 = rightY(c.oldStart), r1 = r0 + CGFloat(c.oldCount) * lineHeight
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 0, y: l0))
            p.curve(to: NSPoint(x: bounds.width, y: r0), controlPoint1: NSPoint(x: bounds.width / 2, y: l0), controlPoint2: NSPoint(x: bounds.width / 2, y: r0))
            p.line(to: NSPoint(x: bounds.width, y: r1))
            p.curve(to: NSPoint(x: 0, y: l1), controlPoint1: NSPoint(x: bounds.width / 2, y: r1), controlPoint2: NSPoint(x: bounds.width / 2, y: l1))
            p.close()
            color.withAlphaComponent(0.18).setFill()
            p.fill()
            color.withAlphaComponent(0.6).setStroke()
            p.lineWidth = 1
            p.stroke()
        }
        for m in insertionMarkers {
            color(for: m.kind).setFill()
            let x = m.leftSide ? 0 : bounds.width - 10
            NSRect(x: x, y: m.y - 1, width: 10, height: 2).fill()
            NSBezierPath(ovalIn: NSRect(x: m.leftSide ? 0 : bounds.width - 5, y: m.y - 2.5, width: 5, height: 5)).fill()
        }
    }

    private func color(for k: LineDiff.Row.Kind) -> NSColor {
        k == .added ? .systemGreen : (k == .removed ? .systemRed : .systemBlue)
    }

    struct InsertionMarker: Equatable { var leftSide: Bool; var row: Int; var y: CGFloat; var kind: LineDiff.Row.Kind }
    var insertionMarkers: [InsertionMarker] {
        guard let leftY, let rightY else { return [] }
        return changes.compactMap { c in
            if c.newCount == 0 { return InsertionMarker(leftSide: true, row: c.newStart, y: leftY(c.newStart), kind: c.kind) }
            if c.oldCount == 0 { return InsertionMarker(leftSide: false, row: c.oldStart, y: rightY(c.oldStart), kind: c.kind) }
            return nil
        }
    }
}

extension SourceEditorController {
    public var comparisonStyle: ComparisonStyle {
        get { review.style }
        set { review.style = newValue }
    }
    public var isShowingInlineComparison: Bool { review.inlineShown }
    public var reviewChanges: [ReviewChange] { review.changes }
    public var reviewBar: CodeReviewBar { review.bar }
    public var currentReviewChange: Int? { review.current }

    public func showInlineComparison(baseline: String, source: ReviewSource) {
        _ = view
        hideComparison()
        review.baseline = baseline
        review.rightSource = source
        review.inlineShown = true
        refreshInlineComparison()
        installReviewBar()
    }

    public func hideInlineComparison() {
        guard review.inlineShown else { return }
        review.inlineShown = false
        review.changes = []
        review.current = nil
        textView.reviewMarks = [:]
        gutter.marks.changes = [:]
        removeReviewBar()
    }

    func removeReviewBar() {
        if let host = review.host { host(nil) } else { review.bar.removeFromSuperview() }
    }

    func refreshInlineComparison() {
        guard review.inlineShown else { return }
        let rows = LineDiff.sideBySide(LineDiff.diff(LineDiff.lines(review.baseline), LineDiff.lines(textView.string)))
        review.changes = CodeReviewModel.changes(rows)
        let marks = CodeReviewModel.lineMarks(review.changes)
        textView.reviewMarks = marks
        gutter.marks.changes = marks
        if let c = review.current, c >= review.changes.count { review.current = nil }
        updateReviewBar()
    }

    func installReviewBar() {
        let bar = review.bar
        bar.onStep = { [weak self] f in self?.stepReviewChange(forward: f) }
        if let host = review.host { bar.wantsLayer = false; host(bar); updateReviewBar(); return }
        guard bar.superview == nil else { updateReviewBar(); return }
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor), bar.heightAnchor.constraint(equalToConstant: 24),
        ])
        bar.onStep = { [weak self] f in self?.stepReviewChange(forward: f) }
        updateReviewBar()
    }

    func updateReviewBar() {
        review.bar.count.stringValue = CodeReviewModel.stepperTitle(review.changes.count)
        review.bar.leftSource.title = review.leftSource.title
        review.bar.rightSource.title = review.rightSource.title
        review.bar.previous.isEnabled = !review.changes.isEmpty
        review.bar.next.isEnabled = !review.changes.isEmpty
    }

    @discardableResult
    public func stepReviewChange(forward: Bool) -> Int? {
        review.current = CodeReviewModel.step(from: review.current, count: review.changes.count, forward: forward)
        if let c = review.current {
            let line = max(1, review.changes[c].newStart)
            if line <= textView.lineIndex.lineCount { reveal(line: line) }
        }
        return review.current
    }

    @discardableResult
    public func selectReviewChange(containing line: Int) -> Int? {
        guard let i = review.changes.firstIndex(where: { line >= $0.newStart && line < $0.newStart + max($0.newCount, 1) }) else { return nil }
        review.current = i
        reveal(line: min(max(1, review.changes[i].newStart), textView.lineIndex.lineCount))
        updateReviewBar()
        return i
    }

    func swapReviewSources() {
        swap(&review.leftSource, &review.rightSource)
        updateReviewBar()
    }

    func setReviewSource(_ s: ReviewSource, left: Bool) {
        if left { review.leftSource = s } else { review.rightSource = s }
        updateReviewBar()
    }
}

extension SourceTextView {
    func drawReviewMarks(in rect: NSRect) {
        for (line, kind) in reviewMarks {
            guard let r = lineRect(line), r.intersects(rect) else { continue }
            if kind == .removed {
                NSColor.systemRed.withAlphaComponent(0.7).setFill()
                NSRect(x: r.minX, y: r.minY, width: r.width, height: 1.5).fill()
            } else {
                (kind == .added ? NSColor.systemGreen : NSColor.systemBlue).withAlphaComponent(0.10).setFill()
                r.fill()
            }
        }
    }
}

extension SourceEditorController {
    public func showSideBySideComparison(baseline: String, source: ReviewSource) {
        _ = view
        hideInlineComparison()
        review.rightSource = source
        let title = (fileURL?.lastPathComponent ?? "") + (source == .lastCommit ? " (HEAD)" : " (\(source.title))")
        if let leftText = review.leftText {
            comparison.show(old: baseline, new: leftText, oldTitle: title,
                            newTitle: (fileURL?.lastPathComponent ?? "") + " (\(review.leftSource.title))")
            comparison.isHidden = false
            scrollView.isHidden = true
            minimap.isHidden = true
        } else {
            showComparison(old: baseline, oldTitle: title)
        }
        comparison.onWorkingCopyEdit = review.leftText == nil ? { [weak self] text in
            guard let self else { return }
            self.textView.string = text
            self.textView.didChangeText()
            self.review.changes = CodeReviewModel.changes(self.comparison.rows)
            self.updateReviewBar()
        } : nil
        review.changes = CodeReviewModel.changes(comparison.rows)
        review.current = nil
        installReviewBar()
    }
}
