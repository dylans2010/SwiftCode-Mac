import Foundation

public enum EditorMetrics {

    public static let referenceFontSize = 13.0
    public static func lineHeight(fontSize: Double) -> Double { (fontSize * 18 / referenceFontSize).rounded() }
    public static func advance(fontAdvance: Double) -> Double { max(1, fontAdvance.rounded()) }
    public static let codeColumn = 51.0
    public static let firstLineInset = 7.0
    public static let textToMinimap = 10.0
    public static let wrappedIndentColumns = 4

    public static func wrappedIndent(of line: Substring, tabWidth: Int, extra: Int = wrappedIndentColumns) -> Int {
        var col = 0
        for ch in line {
            if ch == " " { col += 1 } else if ch == "\t" { col += tabWidth - col % max(1, tabWidth) } else { break }
        }
        return col + extra
    }

    public static let lineNumberEnd = 38.0
    public static let currentLineBandStart = 14.0
    public static let currentLineBandRadius = 4.0
    public static func lineNumberFontSize(sourceSize: Double) -> Double { (sourceSize * 11 / referenceFontSize).rounded() }

    public static let stickyHeaderTopPad = 2.0
    public static let stickyHeaderSeparator = 2.0
    public static func stickyHeaderHeight(rows: Int, lineHeight: Double) -> Double {
        rows > 0 ? stickyHeaderTopPad + lineHeight * Double(rows) : 0
    }

    public static let jumpBarBand = 32.0
    public static let jumpBarSeparator = 2.0
    public static let barVeil = 0.035
    public static let jumpBarOverBlur = 0.3
    public static let bottomBarSeparatorInk = 0.157

    public static let minimapWidthRange = 59.0...135.0
    public static func minimapWidth(editorWidth: Double) -> Double {
        guard editorWidth > 0 else { return 0 }
        return min(minimapWidthRange.upperBound, max(minimapWidthRange.lowerBound, (editorWidth * 0.15).rounded(.down)))
    }
    public static let minimapSeparator = 1.0
    public static let minimapScale = 1.0 / 6
    public static let minimapBarHeight = 2.0
    public static let minimapLinePitch = 3.0
    public static let minimapTextInset = 14.0
    public static let minimapInk = 0.35

    public static func minimapOffset(contentHeight: Double, viewHeight: Double, fraction: Double) -> Double {
        guard contentHeight > viewHeight else { return 0 }
        return (contentHeight - viewHeight) * min(1, max(0, fraction))
    }

    public static let inspectorSlideDuration = 0.225
    public static let inspectorSlideCurve = (x1: 0.8, y1: 0.4, x2: 0.65, y2: 1.0)
    public static let inspectorSlideTable: [(ms: Double, progress: Double)] = [
        (0, 0), (21, 0.01), (41, 0.05), (63, 0.17), (86, 0.25), (108, 0.31), (127, 0.47),
        (147, 0.58), (165, 0.74), (183, 0.92), (202, 0.97), (221, 0.98), (225, 1),
    ]

    public static func inspectorSlideDelay(show: Bool) -> Double { show ? 0.118 : 0.043 }
    public static func inspectorSlideMotion(show: Bool) -> Double { show ? 0.240 : 0.248 }
    public static let inspectorSlideEaseInOut = (x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0)

    public static func inspectorSlideProgress(elapsed: Double, show: Bool) -> Double {
        let t = (elapsed - inspectorSlideDelay(show: show)) / inspectorSlideMotion(show: show)
        let c = inspectorSlideEaseInOut
        return cubicBezier(t, x1: c.x1, y1: c.y1, x2: c.x2, y2: c.y2)
    }
    public static func inspectorSlideTotal(show: Bool) -> Double { inspectorSlideDelay(show: show) + inspectorSlideMotion(show: show) }

    public static func inspectorSlideProgress(_ t: Double) -> Double {
        let ms = min(1, max(0, t)) * inspectorSlideDuration * 1000
        let table = inspectorSlideTable
        guard let i = table.firstIndex(where: { $0.ms >= ms }) else { return 1 }
        if i == 0 { return table[0].progress }
        let a = table[i - 1], b = table[i]
        return a.progress + (b.progress - a.progress) * (ms - a.ms) / max(1e-9, b.ms - a.ms)
    }

    public static func inspectorSlideBezierProgress(_ t: Double) -> Double {
        let c = inspectorSlideCurve
        return cubicBezier(t, x1: c.x1, y1: c.y1, x2: c.x2, y2: c.y2)
    }

    public static func cubicBezier(_ x: Double, x1: Double, y1: Double, x2: Double, y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bez(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            t = (lo + hi) / 2
            if bez(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return bez(t, y1, y2)
    }
}
