import AppKit
import SwiftCodeBuild
import SwiftCodeIDECore

public enum InlineIssueLayout {
    public static func primary(_ list: [Diagnostic]) -> Diagnostic? {
        let rank: [Diagnostic.Severity: Int] = [.error: 0, .warning: 1, .note: 2, .remark: 3]
        return list.min { (rank[$0.severity] ?? 9) < (rank[$1.severity] ?? 9) }
    }

    public static func symbolName(_ s: Diagnostic.Severity) -> String {
        switch s {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .note, .remark: "info.circle.fill"
        }
    }

    @MainActor public static func color(_ s: Diagnostic.Severity, stale: Bool) -> NSColor {
        if stale { return .systemGray }
        switch s {
        case .error: return Theme.errorColor
        case .warning: return Theme.warningColor
        case .note, .remark: return .systemBlue
        }
    }

    public static func truncate(_ message: String, toWidth width: CGFloat, measure: (String) -> CGFloat) -> String {
        let oneLine = message.components(separatedBy: .newlines).first ?? message
        if measure(oneLine) <= width { return oneLine }
        if measure("…") > width { return "" }
        var chars = Array(oneLine)
        var lo = 0, hi = chars.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if measure(String(chars[..<mid]) + "…") <= width { lo = mid } else { hi = mid - 1 }
        }
        chars = Array(chars[..<lo])
        while chars.last == " " { chars.removeLast() }
        return String(chars) + "…"
    }

    public static func underlineRange(column: Int, lineRange: NSRange, in text: NSString) -> NSRange? {
        var end = NSMaxRange(lineRange)
        while end > lineRange.location, [10, 13].contains(text.character(at: end - 1)) { end -= 1 }
        guard end > lineRange.location else { return nil }
        func isIdent(_ c: unichar) -> Bool {
            guard let s = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(s) || c == 95
        }
        func isBlank(_ c: unichar) -> Bool { c == 32 || c == 9 }
        var start: Int
        if column > 0 {
            start = min(lineRange.location + column - 1, end - 1)
        } else {
            start = lineRange.location
            while start < end, isBlank(text.character(at: start)) { start += 1 }
            if start == end { return nil }
        }
        let c0 = text.character(at: start)
        if isBlank(c0) { return NSRange(location: start, length: 1) }
        var stop = start + 1
        if isIdent(c0) {
            while stop < end, isIdent(text.character(at: stop)) { stop += 1 }
        } else if column > 0 {
        } else {
            while stop < end, !isBlank(text.character(at: stop)) { stop += 1 }
        }
        return NSRange(location: start, length: stop - start)
    }
}

extension SourceTextView {
    func drawIssueAnnotations(in rect: NSRect) {
        guard showsIssues else { return }
        let ns = string as NSString
        for (line, list) in issues {
            guard let first = InlineIssueLayout.primary(list), let r = lineRect(line), r.intersects(rect) else { continue }
            let color = InlineIssueLayout.color(first.severity, stale: issuesStale)
            if displayState.minimizedIssues {
                let size: CGFloat = 12
                if let img = NSImage(systemSymbolName: InlineIssueLayout.symbolName(first.severity), accessibilityDescription: first.severity.rawValue) {
                    let tinted = img.withSymbolConfiguration(.init(paletteColors: [color])) ?? img
                    tinted.draw(in: NSRect(x: r.maxX - size - 8, y: r.midY - size / 2, width: size, height: size))
                }
                continue
            }
            color.withAlphaComponent(issuesStale ? 0.08 : 0.12).setFill()
            r.fill()

            if let lr = lineIndex.range(ofLine: line),
               let u = InlineIssueLayout.underlineRange(column: first.location?.column ?? 0, lineRange: lr, in: ns) {
                color.setStroke()
                for seg in segmentRects(u) {
                    let p = NSBezierPath()
                    p.lineWidth = 1
                    var x = seg.minX
                    let y = seg.maxY - 1.5
                    p.move(to: NSPoint(x: x, y: y))
                    var up = true
                    while x < seg.maxX {
                        x = min(x + 2, seg.maxX)
                        p.line(to: NSPoint(x: x, y: up ? y - 1.5 : y))
                        up.toggle()
                    }
                    p.stroke()
                }
            }

            let font = NSFont.systemFont(ofSize: 11)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: issuesStale ? NSColor.secondaryLabelColor : NSColor.labelColor]
            let textEnd = lineIndex.range(ofLine: line).flatMap { lr -> CGFloat? in
                var e = NSMaxRange(lr)
                while e > lr.location, [10, 13].contains(ns.character(at: e - 1)) { e -= 1 }
                return segmentRects(NSRange(location: max(lr.location, e - 1), length: e > lr.location ? 1 : 0)).first?.maxX
            } ?? r.minX
            let iconSize: CGFloat = 12, pad: CGFloat = 6
            let minX = textEnd + 16
            let available = r.maxX - minX - iconSize - pad * 3
            let msg = InlineIssueLayout.truncate(first.message, toWidth: max(0, min(available, 600))) {
                ($0 as NSString).size(withAttributes: attrs).width
            }
            let textW = (msg as NSString).size(withAttributes: attrs).width
            let boxW = iconSize + pad * 3 + textW
            let box = NSRect(x: max(minX, r.maxX - boxW - 4), y: r.minY, width: boxW, height: r.height)
            guard box.width > iconSize else { continue }
            color.withAlphaComponent(issuesStale ? 0.18 : 0.28).setFill()
            NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            if let img = NSImage(systemSymbolName: InlineIssueLayout.symbolName(first.severity), accessibilityDescription: first.severity.rawValue) {
                let tinted = img.withSymbolConfiguration(.init(paletteColors: [color])) ?? img
                tinted.draw(in: NSRect(x: box.minX + pad, y: box.midY - iconSize / 2, width: iconSize, height: iconSize))
            }
            let size = (msg as NSString).size(withAttributes: attrs)
            (msg as NSString).draw(at: NSPoint(x: box.minX + pad * 2 + iconSize, y: box.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
