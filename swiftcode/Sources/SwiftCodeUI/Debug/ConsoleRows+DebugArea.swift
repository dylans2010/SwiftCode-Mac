import AppKit
import SwiftCodeIDECore

extension DebugAreaController {
    public var selectedConsoleRow: Int? {
        _ = view
        let shown = consoleView.string as NSString
        let location = min(consoleView.selectedRange().location, shown.length)
        guard shown.length > 0 else { return nil }
        var shownLine = 0
        var i = 0
        while i < location { if shown.character(at: i) == 10 { shownLine += 1 }; i += 1 }
        let f = consoleSearch.stringValue
        guard !f.isEmpty else { return shownLine }
        let raw = consoleRaw.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = raw.indices.filter { raw[$0].localizedCaseInsensitiveContains(f) }
        return kept.indices.contains(shownLine) ? kept[shownLine] : nil
    }

    public func placeConsoleCaret(line: Int) {
        _ = view
        let ns = consoleView.string as NSString
        var loc = 0
        var n = 0
        while n < line, loc < ns.length {
            let r = ns.range(of: "\n", range: NSRange(location: loc, length: ns.length - loc))
            guard r.location != NSNotFound else { break }
            loc = NSMaxRange(r)
            n += 1
        }
        consoleView.setSelectedRange(NSRange(location: loc, length: 0))
    }

    @discardableResult
    public func selectLastOutput() -> String? {
        _ = view
        guard let r = ConsoleRows.lastParagraph(in: consoleView.string) else { return nil }
        consoleView.setSelectedRange(r)
        consoleView.scrollRangeToVisible(r)
        view.window?.makeFirstResponder(consoleView)
        return (consoleView.string as NSString).substring(with: r)
    }

    public var consoleSelection: String {
        _ = view
        return (consoleView.string as NSString).substring(with: consoleView.selectedRange())
    }
}
