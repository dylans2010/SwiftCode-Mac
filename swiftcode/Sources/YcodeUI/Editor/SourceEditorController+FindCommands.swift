import AppKit
import YcodeIDECore

extension SourceEditorController {
    public func selectFindMatch(_ range: NSRange) {
        _ = view
        let len = (textView.string as NSString).length
        let r = NSRange(location: min(range.location, len), length: max(0, min(range.length, len - min(range.location, len))))
        textView.setSelectedRange(r)
        textView.scrollRangeToVisible(r)
    }

    @objc public func findAndSelectNext(_ sender: Any?) { findAndSelect(forward: true) }
    @objc public func findAndSelectPrevious(_ sender: Any?) { findAndSelect(forward: false) }

    public func findAndSelect(forward: Bool) {
        if find.matches.isEmpty { findChanged() }
        addToSelection(find.matches, forward: forward)
    }

    @objc public func selectNextOccurrence(_ sender: Any?) { selectOccurrence(forward: true) }
    @objc public func selectPreviousOccurrence(_ sender: Any?) { selectOccurrence(forward: false) }

    public func selectOccurrence(forward: Bool) {
        _ = view
        let ns = textView.string as NSString
        let ranges = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard let anchor = forward ? ranges.last : ranges.first else {
            let r = Self.wordRange(in: ns, at: textView.selectedRange().location)
            if r.length > 0 { textView.setSelectedRange(r) } else { NSSound.beep() }
            return
        }
        let needle = ns.substring(with: anchor)
        var all: [NSRange] = []
        var from = 0
        while from < ns.length {
            let r = ns.range(of: needle, options: [.literal], range: NSRange(location: from, length: ns.length - from))
            guard r.location != NSNotFound else { break }
            all.append(r)
            from = r.location + max(1, r.length)
        }
        addToSelection(all, forward: forward)
    }

    func addToSelection(_ candidates: [NSRange], forward: Bool) {
        let ranges = textView.selectedRanges.map(\.rangeValue)
        let chosen = Set(ranges.filter { $0.length > 0 }.map { "\($0.location):\($0.length)" })
        let free = candidates.filter { !chosen.contains("\($0.location):\($0.length)") }
        guard !free.isEmpty else { NSSound.beep(); return }
        let next: NSRange
        if forward {
            let end = ranges.map { NSMaxRange($0) }.max() ?? 0
            next = free.first { $0.location >= end } ?? free[0]
        } else {
            let start = ranges.map(\.location).min() ?? 0
            next = free.last { NSMaxRange($0) <= start } ?? free[free.count - 1]
        }
        let kept = ranges.filter { $0.length > 0 }
        textView.setSelectedRanges((kept + [next]).sorted { $0.location < $1.location }.map { NSValue(range: $0) },
                                   affinity: .downstream, stillSelecting: false)
        textView.scrollRangeToVisible(next)
    }

    @objc public func replaceAndFindPrevious(_ sender: Any?) {
        replaceCurrent()
        findStep(forward: false)
    }

    @objc public func useSelectionForReplace(_ sender: Any?) {
        _ = view
        let sel = textView.selectedRange()
        guard sel.length > 0 else { NSSound.beep(); return }
        findBar.replaceField.stringValue = (textView.string as NSString).substring(with: sel)
    }

    public var findBarReplacement: String { findBar.replaceField.stringValue }

    static func wordRange(in ns: NSString, at offset: Int) -> NSRange {
        func isWord(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(s) || c == 95
        }
        var a = min(offset, ns.length), b = a
        while a > 0, isWord(ns.character(at: a - 1)) { a -= 1 }
        while b < ns.length, isWord(ns.character(at: b)) { b += 1 }
        return NSRange(location: a, length: b - a)
    }
}
