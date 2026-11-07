import Foundation
import SwiftCodeSyntax

public enum MergeSheetMetrics {
    public static let sheetInset = 24.0
    public static let cornerRadius = 16.0
    public static let boxSideInset = 20.0
    public static let boxTopInset = 11.5
    public static let fileListWidth = 198.0
    public static let fileListHeader = 27.0
    public static let fileRowHeight = 24.0
    public static let fileIconX = 31.5
    public static let fileNameX = 52.5
    public static let badgeSize = 12.0
    public static let badgeTrailing = 8.0
    public static let filterHeight = 21.0
    public static let filterBottom = 3.5
    public static let segmentHeight = 17.0
    public static let jumpBarHeight = 36.0
    public static let footerHeight = 27.0
    public static let gutterWidth = 46.0
    public static let rulerWidth = 17.0
    public static let rulerMarkX = 2.0
    public static let rulerMarkWidth = 10.0
    public static let lineNumberRight = 27.0
    public static let codeX = 41.0
    public static let firstLineTop = 8.0
    public static let currentLineInset = 8.0
    public static let cellWidth = 8.0
    public static let lineHeight = 18.0
    public static let wrapIndent = 4
    public static let tokenWidth = 38.5
    public static let tokenHeight = 14.0
    public static let tokenLeft = 3.5
    public static let chevronCircle = 11.0
    public static let wordInset = 1.0
    public static let footerTextX = 9.5
    public static let stepperWidth = 60.0
    public static let buttonWidth = 84.0
    public static let buttonSpacing = 12.0
    public static let buttonGap = 21.5
    public static let buttonHeight = 24.0
    public static let bottomMargin = 18.0

    public static let alertWidth = 420.0
    public static let alertHeight = 133.0
    public static let alertIcon = 55.0
    public static let alertIconOrigin = (x: 28.5, y: 22.0)
    public static let alertTextX = 106.0
    public static let alertTitleTop = 20.0
    public static let alertMessageTop = 59.5
    public static let alertButtonHeight = 20.0
    public static let alertCancelWidth = 58.0
    public static let alertMergeWidth = 79.0
    public static let alertButtonSpacing = 14.5
    public static let alertButtonTrailing = 20.5
    public static let alertButtonBottom = 18.0
    public static let alertChooserHeight = 30.0

    public static func sheetFrame(window size: (width: Double, height: Double), toolbarBottom: Double) -> Rect {
        let h = max(240, size.height - toolbarBottom - sheetInset)
        return Rect(x: sheetInset, y: toolbarBottom, width: max(400, size.width - 2 * sheetInset), height: h)
    }

    public static func contentBox(sheet size: (width: Double, height: Double)) -> Rect {
        let bottom = size.height - bottomMargin - buttonHeight - buttonGap
        return Rect(x: boxSideInset, y: boxTopInset, width: size.width - 2 * boxSideInset, height: max(120, bottom - boxTopInset))
    }

    public static func alertFrame(window size: (width: Double, height: Double), chooser: Bool = false) -> Rect {
        let h = alertHeight + (chooser ? alertChooserHeight : 0)
        return Rect(x: ((size.width - alertWidth) / 2).rounded(.down), y: ((size.height - h) / 2).rounded(.down), width: alertWidth, height: h)
    }

    public struct Columns: Equatable, Sendable {
        public var fileList: Range1
        public var left: Range1
        public var gutter: Range1
        public var right: Range1
        public var rightText: Range1
        public var ruler: Range1
    }

    public static func columns(boxWidth: Double) -> Columns {
        let inner = boxWidth - 2
        let paneSpace = inner - fileListWidth - 1 - gutterWidth - 2 - rulerWidth
        let pane = (paneSpace / 2).rounded(.down)
        let fileList = Range1(1, fileListWidth)
        let left = Range1(fileList.end + 1, pane)
        let gutter = Range1(left.end + 1, gutterWidth)
        let rightStart = gutter.end + 1
        let right = Range1(rightStart, boxWidth - 1 - rightStart)
        let rightText = Range1(rightStart, right.length - rulerWidth)
        return Columns(fileList: fileList, left: left, gutter: gutter, right: right, rightText: rightText,
                       ruler: Range1(rightText.end, rulerWidth))
    }

    public static func columnsOfText(paneWidth: Double) -> Int {
        max(8, Int(((paneWidth - codeX - currentLineInset) / cellWidth).rounded(.down)))
    }

    public struct Rect: Equatable, Sendable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    public struct Range1: Equatable, Sendable {
        public var start, length: Double
        public init(_ start: Double, _ length: Double) { self.start = start; self.length = length }
        public var end: Double { start + length }
    }
}

public struct MergeSheetPalette: Equatable, Sendable {
    public var sheet: UInt32
    public var veilOpacity: Double
    public var boxBorder: UInt32
    public var columnRule: UInt32
    public var bandRule: UInt32
    public var footerRule: UInt32
    public var label: UInt32
    public var secondaryLabel: UInt32
    public var disabledLabel: UInt32
    public var accent: UInt32
    public var segmentPill: UInt32
    public var selection: UInt32
    public var badge: UInt32
    public var badgeLetter: UInt32
    public var filterFill: UInt32
    public var filterPlaceholder: UInt32
    public var lineNumber: UInt32
    public var currentLineNumber: UInt32
    public var currentLine: UInt32
    public var gutter: UInt32
    public var gutterConflict: UInt32
    public var gutterClean: UInt32
    public var conflictRow: UInt32
    public var conflictWord: UInt32
    public var cleanRow: UInt32
    public var selectedRule: UInt32
    public var decidedRule: UInt32
    public var token: UInt32
    public var selectedToken: UInt32
    public var selectedTokenRim: UInt32
    public var tokenInk: UInt32
    public var chevronCircle: UInt32
    public var selectedChevronCircle: UInt32
    public var rulerConflict: UInt32
    public var rulerClean: UInt32
    public var button: UInt32
    public var buttonLabel: UInt32
    public var disabledButton: UInt32
    public var disabledButtonLabel: UInt32
    public var folder: UInt32

    public static let light = MergeSheetPalette(
        sheet: 0xFFFFFF, veilOpacity: 0.196, boxBorder: 0xBFBFBF, columnRule: 0xD7D7D7, bandRule: 0xE5E5E5, footerRule: 0xE6E6E6,
        label: 0x262626, secondaryLabel: 0x7A7A7A, disabledLabel: 0xA0A0A0, accent: 0x007AFF, segmentPill: 0xD1E7FF,
        selection: 0x0064E1, badge: 0xFFFFFF, badgeLetter: 0xFF383C, filterFill: 0xF3F3F3, filterPlaceholder: 0x7A7A7A,
        lineNumber: 0xB7B2B4, currentLineNumber: 0x322529, currentLine: 0xEEEEED,
        gutter: 0xF5F5F4, gutterConflict: 0xF9D5D5, gutterClean: 0xD1E4F8,
        conflictRow: 0xFFDCDD, conflictWord: 0xFF9A9D, cleanRow: 0xD6EBFE, selectedRule: 0xDA5559, decidedRule: 0xFF656A,
        token: 0x575757, selectedToken: 0x6D2A2D, selectedTokenRim: 0xDA5559, tokenInk: 0xFFFFFF,
        chevronCircle: 0x6B6C6B, selectedChevronCircle: 0xFF6569, rulerConflict: 0xFDB9B5, rulerClean: 0xD4D4D4,
        button: 0xEDEDED, buttonLabel: 0x252525, disabledButton: 0xF5F5F5, disabledButtonLabel: 0xB6B6B6, folder: 0x3A9AF5)

    public static let dark = MergeSheetPalette(
        sheet: 0x1F1F1F, veilOpacity: 0.32, boxBorder: 0x3D3D3D, columnRule: 0x383838, bandRule: 0x333333, footerRule: 0x333333,
        label: 0xE6E6E6, secondaryLabel: 0x8C8C8C, disabledLabel: 0x6A6A6A, accent: 0x0A84FF, segmentPill: 0x1D3A5C,
        selection: 0x0059CF, badge: 0xFFFFFF, badgeLetter: 0xFF453A, filterFill: 0x2B2B2B, filterPlaceholder: 0x8C8C8C,
        lineNumber: 0x6E6A6C, currentLineNumber: 0xE2DADD, currentLine: 0x2A2A2A,
        gutter: 0x252525, gutterConflict: 0x47272A, gutterClean: 0x1F3550,
        conflictRow: 0x4A2629, conflictWord: 0x7D3337, cleanRow: 0x1E3A57, selectedRule: 0xE0666A, decidedRule: 0xFF7377,
        token: 0x8A8A8A, selectedToken: 0x8E3337, selectedTokenRim: 0xE0666A, tokenInk: 0xFFFFFF,
        chevronCircle: 0x9C9C9C, selectedChevronCircle: 0xFF6E72, rulerConflict: 0x9B4B48, rulerClean: 0x5A5A5A,
        button: 0x3A3A3A, buttonLabel: 0xE6E6E6, disabledButton: 0x2C2C2C, disabledButtonLabel: 0x666666, folder: 0x3A9AF5)

    public static func forDark(_ dark: Bool) -> MergeSheetPalette { dark ? .dark : .light }

    public static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}

public enum MergeSheetMotion {
    public static let veilIn = 0.255
    public static let alertIn = 0.017
    public static let alertOut = 0.09
    public static let sheetFade = 0.09
    public static let sheetSlide = 0.2
    public static let slideDistance = 32.0
    public static let slideCurve = (x1: 0.4, y1: 0.3, x2: 0.6, y2: 1.0)
    public static let sheetOutFade = 0.09
    public static let sheetOutSlide = 0.2
    public static let chooseDismissal = 0.33

    public static func sheetOpacity(at t: Double) -> Double {
        min(1, max(0, t / sheetFade))
    }

    public static func sheetOffset(at t: Double, reduceMotion: Bool = false) -> Double {
        guard !reduceMotion else { return 0 }
        let p = bezier(min(1, max(0, t / sheetSlide)), slideCurve)
        return -slideDistance * (1 - p)
    }

    public static func veilProgress(at t: Double) -> Double {
        let p = min(1, max(0, t / veilIn))
        return 1 - (1 - p) * (1 - p) * (1 - p)
    }

    public static func bezier(_ x: Double, _ c: (x1: Double, y1: Double, x2: Double, y2: Double)) -> Double {
        func coord(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            t = (lo + hi) / 2
            if coord(t, c.x1, c.x2) < x { lo = t } else { hi = t }
        }
        return coord(t, c.y1, c.y2)
    }
}

public enum MergeSheetText {
    static func q(_ s: String) -> String { "\u{201C}\(s)\u{201D}" }

    public static func alertTitle(branch: String) -> String { "Are you sure you want to merge from \(q(branch))?" }
    public static func alertMessage(branch: String, current: String) -> String {
        "Changes from \(q(branch)) will be merged into your current branch (\(q(current)))."
    }
    public static let cancel = "Cancel"
    public static let merge = "Merge"
    public static let hierarchical = "Hierarchical"
    public static let flat = "Flat"
    public static let filter = "Filter"
    public static let noSelection = "No Selection"
    public static let noEditor = "No Editor"
    public static let loading = "Loading\u{2026}"

    public static let chooseTitles = ["Choose Left", "Choose Right", "Choose Left Then Right", "Choose Right Then Left"]
    public static let chooseChoices: [MergeDocument.Choice] = [.ours, .theirs, .oursThenTheirs, .theirsThenOurs]
    public static let chooseSeparatorAfter = 1

    public static func cancelTitle(verb: String) -> String { "Abort the \(verb.isEmpty ? "operation" : verb.lowercased())?" }
    public static func cancelMessage(verb: String) -> String {
        let v = verb.isEmpty ? "operation" : verb.lowercased()
        return "The changes chosen in this sheet are discarded and the branch returns to where it was before the \(v)."
    }
}

public enum MergeSheetToken {
    public static func glyph(choice: MergeDocument.Choice, kind: ThreeWayMerge.Chunk.Kind) -> String {
        if kind != .conflict, choice == MergeDocument.defaultChoice(kind) { return "3" }
        switch choice {
        case .unresolved: return "?"
        case .theirs: return "1"
        case .ours: return "2"
        case .oursThenTheirs: return "4"
        case .theirsThenOurs: return "5"
        case .base: return "6"
        case .custom: return "7"
        }
    }
}

public struct MergeSheetRow: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case same, conflict, clean }
    public struct Side: Equatable, Sendable {
        public var number: Int
        public var text: String
        public var words: [Range<Int>]
    }
    public var left: Side?
    public var right: Side?
    public var kind: Kind
    public var hunk: Int?
    public var isFirstOfHunk: Bool
    public var isLastOfHunk: Bool
}

public enum MergeSheetLayout {
    public static func rows(_ doc: MergeDocument) -> [MergeSheetRow] {
        var out: [MergeSheetRow] = []
        var l = 0, r = 0, h = 0
        for (i, c) in doc.chunks.enumerated() {
            if h < doc.hunks.count, doc.hunks[h] == i {
                let left = doc.choices[h] == .unresolved ? c.ours : doc.lines(forHunk: h)
                let right = c.theirs
                let kind: MergeSheetRow.Kind = c.kind == .conflict ? .conflict : .clean
                var lw: [[Range<Int>]] = [], rw: [[Range<Int>]] = []
                if kind == .conflict {
                    for k in 0..<max(c.ours.count, c.theirs.count) {
                        let a = k < c.ours.count ? expandTabs(c.ours[k]) : nil, b = k < c.theirs.count ? expandTabs(c.theirs[k]) : nil
                        let w = changedWords(a ?? "", b ?? "")
                        lw.append(a == nil ? [] : w.left)
                        rw.append(b == nil ? [] : w.right)
                    }
                }
                let n = max(1, left.count, right.count)
                for k in 0..<n {
                    var row = MergeSheetRow(left: nil, right: nil, kind: kind, hunk: h, isFirstOfHunk: k == 0, isLastOfHunk: k == n - 1)
                    if k < left.count {
                        l += 1
                        let t = expandTabs(left[k])
                        row.left = .init(number: l, text: t, words: k < lw.count ? lw[k].filter { $0.upperBound <= t.count } : [])
                    }
                    if k < right.count {
                        r += 1
                        row.right = .init(number: r, text: expandTabs(right[k]), words: k < rw.count ? rw[k] : [])
                    }
                    out.append(row)
                }
                h += 1
            } else {
                for line in c.ours {
                    l += 1; r += 1
                    let t = expandTabs(line)
                    out.append(MergeSheetRow(left: .init(number: l, text: t, words: []), right: .init(number: r, text: t, words: []),
                                             kind: .same, hunk: nil, isFirstOfHunk: false, isLastOfHunk: false))
                }
            }
        }
        return out
    }

    public static func leftText(_ doc: MergeDocument) -> [String] {
        var lines: [String] = []
        var h = 0
        for (i, c) in doc.chunks.enumerated() {
            if h < doc.hunks.count, doc.hunks[h] == i {
                lines += doc.choices[h] == .unresolved ? c.ours : doc.lines(forHunk: h)
                h += 1
            } else {
                lines += c.ours
            }
        }
        return lines
    }

    public static func expandTabs(_ s: String) -> String {
        guard s.contains("\t") else { return s }
        var out = ""
        var col = 0
        for ch in s {
            if ch == "\t" {
                let n = 4 - col % 4
                out += String(repeating: " ", count: n)
                col += n
            } else {
                out.append(ch)
                col += 1
            }
        }
        return out
    }

    public static func changedWords(_ a: String, _ b: String) -> (left: [Range<Int>], right: [Range<Int>]) {
        let ca = Array(a), cb = Array(b)
        let wa = words(a), wb = words(b)
        let sa = wa.map { String(ca[$0]) }, sb = wb.map { String(cb[$0]) }
        let n = sa.count, m = sb.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = sa[i] == sb[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var keepA = Set<Int>(), keepB = Set<Int>()
        var i = 0, j = 0
        while i < n, j < m {
            if sa[i] == sb[j] { keepA.insert(i); keepB.insert(j); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 } else { j += 1 }
        }
        return (wa.indices.filter { !keepA.contains($0) }.map { wa[$0] }, wb.indices.filter { !keepB.contains($0) }.map { wb[$0] })
    }

    static func words(_ s: String) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for (i, ch) in s.enumerated() {
            if ch == " " {
                if let st = start { out.append(st..<i); start = nil }
            } else if start == nil { start = i }
        }
        if let st = start { out.append(st..<s.count) }
        return out
    }

    public struct Segment: Equatable, Sendable {
        public var cells: Range<Int>
        public var column: Int
    }

    public static func wrap(_ text: String, columns: Int) -> [Segment] {
        let chars = Array(text)
        guard chars.count > columns, columns > 8 else { return [Segment(cells: 0..<chars.count, column: 0)] }
        let indent = min(chars.prefix { $0 == " " }.count + MergeSheetMetrics.wrapIndent, columns / 2)
        var out: [Segment] = []
        var start = 0, column = 0
        while start < chars.count {
            let width = columns - column
            if chars.count - start <= width { out.append(Segment(cells: start..<chars.count, column: column)); break }
            var end = start + width
            if let space = chars[(start + 1)..<end].lastIndex(of: " ") { end = space + 1 }
            out.append(Segment(cells: start..<end, column: column))
            start = end
            column = indent
        }
        return out
    }

    public static func height(_ row: MergeSheetRow, columns: Int) -> Double {
        let l = row.left.map { wrap($0.text, columns: columns).count } ?? 1
        let r = row.right.map { wrap($0.text, columns: columns).count } ?? 1
        return Double(max(1, l, r)) * MergeSheetMetrics.lineHeight
    }

    public static func highlight(_ lines: [String], fileName: String) -> [[(text: String, role: SyntaxTokenKind.Role?)]] {
        let language = SyntaxLanguage(fileName: fileName)
        let text = lines.joined(separator: "\n")
        let doc = lines.count <= 20_000 && language != .plain ? SyntaxDocument(text: text, language: language) : nil
        let units = Array(text.utf16)
        var out: [[(text: String, role: SyntaxTokenKind.Role?)]] = []
        out.reserveCapacity(lines.count)
        var start = 0
        for (n, line) in lines.enumerated() {
            let end = start + line.utf16.count
            var runs: [(text: String, role: SyntaxTokenKind.Role?)] = []
            func add(_ a: Int, _ b: Int, _ role: SyntaxTokenKind.Role?) {
                guard b > a else { return }
                let s = String(decoding: units[a..<b], as: UTF16.self)
                if let last = runs.last, last.role == role { runs[runs.count - 1].text += s } else { runs.append((s, role)) }
            }
            var at = start
            if let doc, n < doc.lineCount {
                for t in doc.tokens(onLine: n).sorted(by: { $0.location < $1.location }) {
                    let a = max(t.location, at), b = min(t.end, end)
                    guard a < b else { continue }
                    add(at, a, nil)
                    add(a, b, t.kind.role == .identifier ? nil : t.kind.role)
                    at = b
                }
            }
            add(at, end, nil)
            var col = 0
            out.append(runs.map { run in
                var s = ""
                for ch in run.text {
                    if ch == "\t" { let k = 4 - col % 4; s += String(repeating: " ", count: k); col += k } else { s.append(ch); col += 1 }
                }
                return (s, run.role)
            })
            start = end + 1
        }
        return out
    }
}

public struct MergeSheetFooter: Equatable, Sendable {
    public var repository: String
    public var branch: String
    public var date: Date?
    public var author: String
    public var shortHash: String
    public var isHead: Bool

    public init(repository: String, branch: String, date: Date?, author: String, shortHash: String, isHead: Bool) {
        self.repository = repository
        self.branch = branch
        self.date = date
        self.author = author
        self.shortHash = shortHash
        self.isHead = isHead
    }

    public var dateText: String {
        guard let date else { return "" }
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)/\(String(format: "%02d", (c.year ?? 0) % 100))"
    }

    public var commitText: String {
        [dateText, author, shortHash + (isHead ? " (HEAD)" : "")].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    public static func read(_ repo: GitRepository, integration: GitRepository.IntegrationState, oursLabel: String,
                            theirsLabel: String) -> (left: MergeSheetFooter?, right: MergeSheetFooter?) {
        let name = repo.root.lastPathComponent
        func footer(_ rev: String, _ branch: String, head: Bool) -> MergeSheetFooter? {
            guard let c = repo.commit(rev) else { return nil }
            return MergeSheetFooter(repository: name, branch: branch, date: c.date, author: c.authorName, shortHash: c.shortHash, isHead: head)
        }
        let theirsRev: String = switch integration {
        case .merging: "MERGE_HEAD"
        case .rebasing: "REBASE_HEAD"
        case .cherryPicking(let c): c
        case .reverting(let c): c
        case .none: "stash@{0}"
        }
        return (footer("HEAD", oursLabel, head: true), footer(theirsRev, theirsLabel, head: false))
    }
}
