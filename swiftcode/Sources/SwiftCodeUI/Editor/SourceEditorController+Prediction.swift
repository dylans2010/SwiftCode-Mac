import AppKit
import SwiftCodeCompletion
import SwiftCodeIDECore

struct GhostText: Equatable {
    var anchor: Int
    var text: String
    var expanded: Bool
}

@MainActor
final class PredictionState {
    let session = PredictionSession()
    var pendingEdit: (location: Int, removed: Int, inserted: String)?
    var severalEdits = false
    var expanded = false
    var settingsOverride: PredictiveCompletionSettings?
}

extension SourceEditorController {
    var prediction: PredictionSession { predictionState.session }

    public var predictionSuggestion: PredictionSession.Suggestion? { prediction.suggestion }
    public var shownPredictionText: String? {
        textView.ghostText.map { $0.expanded ? $0.text : PredictionSession.collapsed($0.text) }
    }
    public var predictionSession: PredictionSession { prediction }

    func setUpPrediction() {
        prediction.onSuggestionChange = { [weak self] s in self?.showPrediction(s) }
        prediction.onStatusChange = { [weak self] s in self?.onPredictionStatus?(s) }
        applyPredictionPreferences()
    }

    func applyPredictionPreferences() {
        let p = Preferences.shared
        prediction.assistantOllamaURL = p.sharedOllamaURL
        prediction.settings = predictionState.settingsOverride ?? p.predictiveCompletion
    }

    public var predictionSettingsOverride: PredictiveCompletionSettings? {
        get { predictionState.settingsOverride }
        set {
            predictionState.settingsOverride = newValue
            applyPredictionPreferences()
        }
    }

    func showPrediction(_ s: PredictionSession.Suggestion?) {
        textView.ghostText = s.map { GhostText(anchor: $0.anchor, text: $0.text, expanded: predictionState.expanded) }
    }

    func predictionSnapshot() -> PredictionSession.Snapshot? {
        guard let url = fileURL, textView.isEditable else { return nil }
        let sel = textView.selectedRange()
        let others = predictionOtherFiles?().filter { $0.path != url.path }.map { (path: ($0.path as NSString).lastPathComponent, text: $0.text) } ?? []
        return PredictionSession.Snapshot(text: textView.string, caret: sel.location, selectionLength: sel.length,
                                          path: predictionPath?(url) ?? url.lastPathComponent,
                                          language: CompletionContext.language(forPath: url.path), otherFiles: others)
    }

    func notePredictionEdit(range: NSRange, replacement: String) {
        if predictionState.pendingEdit != nil { predictionState.severalEdits = true }
        predictionState.pendingEdit = (range.location, range.length, replacement)
    }

    func predictionTextDidChange() {
        defer {
            predictionState.pendingEdit = nil
            predictionState.severalEdits = false
        }
        guard let snap = predictionSnapshot(), textView.multipleRanges.isEmpty, !isShowingCompletions else { return prediction.dismiss() }
        let e = predictionState.pendingEdit ?? (snap.caret, 1, "")
        prediction.textDidChange(snap, location: e.location, removed: predictionState.severalEdits ? max(1, e.removed) : e.removed, inserted: e.inserted)
    }

    func predictionSelectionDidChange() {
        guard predictionState.pendingEdit == nil else { return }
        let sel = textView.selectedRange()
        prediction.selectionDidChange(caret: sel.location, length: sel.length)
    }

    @objc public func showPredictiveCompletion(_ sender: Any?) {
        guard let snap = predictionSnapshot() else { return }
        hideCompletions()
        prediction.forceRequest(snap)
    }

    @discardableResult
    public func acceptPrediction(_ unit: PredictionSession.AcceptUnit) -> Bool {
        guard let s = prediction.suggestion, let text = prediction.acceptText(unit), !text.isEmpty else { return false }
        let at = NSRange(location: s.anchor, length: 0)
        textView.insertText(text, replacementRange: at)
        textView.setSelectedRange(NSRange(location: s.anchor + (text as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        return true
    }

    public func dismissPrediction() { prediction.dismiss() }

    func handlePredictionKey(_ e: NSEvent) -> Bool {
        guard prediction.suggestion != nil else { return false }
        let flags = e.modifierFlags.intersection([.shift, .command, .option, .control])
        switch e.keyCode {
        case 48 where flags.isEmpty: return acceptPrediction(predictionState.expanded ? .all : .shown)
        case 48 where flags == .option: return acceptPrediction(.all)
        case 48 where flags == .control: return acceptPrediction(.word)
        case 53:
            dismissPrediction()
            return true
        default: return false
        }
    }

    func predictionFlagsChanged(_ e: NSEvent) {
        let expanded = e.modifierFlags.intersection([.shift, .command, .option, .control]) == .option
        guard expanded != predictionState.expanded else { return }
        predictionState.expanded = expanded
        showPrediction(prediction.suggestion)
    }
}

final class GhostTextOverlay: NSView {
    weak var textView: SourceTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { textView?.drawGhostText(in: dirtyRect) }
}

extension SourceTextView {
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview !== ghostOverlay, ghostOverlay.superview === self { addSubview(ghostOverlay, positioned: .above, relativeTo: nil) }
    }

    func updateGhostOverlay() {
        guard ghostText != nil else {
            ghostOverlay.removeFromSuperview()
            return
        }
        ghostOverlay.textView = self
        ghostOverlay.frame = bounds
        ghostOverlay.autoresizingMask = [.width, .height]
        if ghostOverlay.superview !== self || subviews.last !== ghostOverlay {
            addSubview(ghostOverlay, positioned: .above, relativeTo: nil)
        }
        ghostOverlay.needsDisplay = true
    }

    func drawGhostText(in dirty: NSRect) {
        guard let g = ghostText, let caret = caretRect(at: g.anchor) else { return }
        let shown = g.expanded ? g.text : PredictionSession.collapsed(g.text)
        let lines = shown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let ghost: [NSAttributedString.Key: Any] = [.font: Theme.font, .foregroundColor: Theme.ghostTextColor]
        let plain: [NSAttributedString.Key: Any] = [.font: Theme.font, .foregroundColor: Theme.textColor]
        let background = backgroundColor
        let ns = string as NSString
        var lineEnd = 0
        ns.getLineStart(nil, end: nil, contentsEnd: &lineEnd, for: NSRange(location: min(g.anchor, ns.length), length: 0))
        let rest = ns.substring(with: NSRange(location: min(g.anchor, ns.length), length: max(0, lineEnd - g.anchor)))
        let first = lines.first ?? ""
        if !first.isEmpty {
            let width = (first as NSString).size(withAttributes: ghost).width
            let x = caret.minX + 1
            if !rest.isEmpty {
                for r in segmentRects(NSRange(location: g.anchor, length: (rest as NSString).length)) {
                    let cover = NSRect(x: max(r.minX, x + 1), y: r.minY, width: r.maxX - max(r.minX, x + 1) + 1, height: r.height)
                    background.setFill()
                    cover.fill()
                    if caretLine != nil, caretLine != highlightedLine {
                        NSColor.labelColor.withAlphaComponent(0.05).setFill()
                        cover.fill(using: .sourceOver)
                    }
                }
                (rest as NSString).draw(at: NSPoint(x: x + width, y: caret.minY), withAttributes: plain)
            }
            (first as NSString).draw(at: NSPoint(x: x, y: caret.minY), withAttributes: ghost)
        }
        guard lines.count > 1 else { return }
        let x0 = textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0)
        let height = caret.height
        let widest = lines.dropFirst().map { ($0 as NSString).size(withAttributes: ghost).width }.max() ?? 0
        let block = NSRect(x: x0 - 2, y: caret.maxY, width: min(bounds.width - x0, widest + 12), height: height * CGFloat(lines.count - 1))
        background.setFill()
        block.fill()
        Theme.ghostTextColor.withAlphaComponent(0.35).setFill()
        NSRect(x: block.minX, y: block.minY, width: 1, height: block.height).fill()
        for (i, l) in lines.dropFirst().enumerated() {
            (l as NSString).draw(at: NSPoint(x: x0, y: caret.maxY + height * CGFloat(i)), withAttributes: ghost)
        }
    }
}
