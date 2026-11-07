import Foundation
import SwiftUI
import YcodeIDECore
import YcodeIDEShell
import YcodeSyntax

struct MergeComparisonView: View {
    var editor: ConflictEditorShellModel
    var palette: MergeSheetPalette
    var leftWidth: CGFloat
    var rightWidth: CGFloat
    var height: CGFloat
    @State private var currentLeft = 1
    @State private var currentRight = 1
    @State private var clicks = MergeClickTracker()
    @State private var layouts = MergeLayoutCache()

    typealias M = MergeSheetMetrics

    var body: some View {
        let state = editor.state
        let name = state.currentFile.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let layout = layouts.layout(state: state, fileName: name, leftWidth: leftWidth, rightWidth: rightWidth, palette: palette)
        let p = palette
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: CGFloat(M.firstLineTop))
                            ForEach(layout.rows.indices, id: \.self) { i in
                                rowView(i, layout)
                                    .id(i)
                            }
                            Color.clear.frame(height: CGFloat(M.firstLineTop))
                        }
                        if state.isEditing, let h = state.currentHunk, let range = layout.rows(ofHunk: h) {
                            let top = CGFloat(M.firstLineTop) + layout.tops[range.lowerBound]
                            let bottom = CGFloat(M.firstLineTop) + layout.tops[range.upperBound - 1] + layout.heights[range.upperBound - 1]
                            let lines = CGFloat(editor.editedText.split(separator: "\n", omittingEmptySubsequences: false).count + 1)
                            handEditor(p)
                                .frame(width: leftWidth - CGFloat(M.codeX) - 4, height: max(bottom - top, lines * CGFloat(M.lineHeight) + 12))
                                .offset(x: CGFloat(M.codeX) - 4, y: top)
                        }
                    }
                    .frame(width: layout.totalWidth, alignment: .topLeading)
                    .background(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            Color(mergeHex: p.sheet).frame(width: leftWidth)
                            Rectangle().fill(Color(mergeHex: p.columnRule)).frame(width: 1)
                            Color(mergeHex: p.gutter).frame(width: CGFloat(M.gutterWidth))
                            Rectangle().fill(Color(mergeHex: p.columnRule)).frame(width: 1)
                            Color(mergeHex: p.sheet).frame(width: rightWidth)
                        }
                        .frame(minHeight: height)
                    }
                }
                .scrollIndicators(.hidden)
                .frame(width: layout.totalWidth, height: height)
                .shellTarget("merge panes")
                MergeRuler(marks: state.rulerMarks(rows: layout.rows), palette: p) { share in
                    let i = Int((share * Double(layout.rows.count)).rounded(.down))
                    if layout.rows.indices.contains(i) { proxy.scrollTo(i, anchor: .center) }
                }
                .frame(width: CGFloat(M.rulerWidth), height: height)
                .shellTarget("merge ruler")
            }
            .onChange(of: editor.revealCount) { _, _ in
                if let h = editor.state.currentHunk, let r = layout.rows(ofHunk: h) { proxy.scrollTo(r.lowerBound, anchor: .center) }
            }
            .onChange(of: state.currentFile) { _, _ in
                currentLeft = 1
                currentRight = 1
                if let h = editor.state.currentHunk, let r = layout.rows(ofHunk: h) { proxy.scrollTo(r.lowerBound, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    func rowView(_ i: Int, _ layout: MergePaneLayout) -> some View {
        let row = layout.rows[i]
        let state = editor.state
        let selected = row.hunk != nil && row.hunk == state.currentHunk
        let decided = selected && (row.hunk.flatMap { state.token(forHunk: $0)?.isDecided } ?? false)
        let input = MergeRowPainter(row: row, layout: layout, currentLeft: currentLeft, currentRight: currentRight,
                                    isSelected: selected, isDecided: decided)
        Canvas { ctx, _ in input.draw(&ctx) }
            .frame(width: layout.totalWidth, height: layout.heights[i])
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.left.map { "Line \($0.number): \($0.text)" } ?? row.right.map { "Line \($0.number): \($0.text)" } ?? "")
            .shellTarget("merge row \(i)")
            .contentShape(Rectangle())
            .onTapGesture(count: 1, coordinateSpace: .local) { pt in click(i, at: pt, layout) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { doubleClick(i, layout) })
            .overlay(alignment: .topLeading) {
                if row.isFirstOfHunk, let h = row.hunk, let t = state.token(forHunk: h) {
                    token(h, t)
                        .offset(x: layout.gutterX + CGFloat(M.tokenLeft), y: (CGFloat(M.lineHeight) - CGFloat(M.tokenHeight)) / 2)
                }
            }
    }

    func click(_ i: Int, at pt: CGPoint, _ layout: MergePaneLayout) {
        let row = layout.rows[i]
        if pt.x < leftWidth, let l = row.left, currentLeft != l.number { currentLeft = l.number }
        if pt.x >= layout.rightX, let r = row.right, currentRight != r.number { currentRight = r.number }
        let isDouble = clicks.isDouble(row: i, left: pt.x < leftWidth)
        guard let h = row.hunk else { return }
        if editor.state.currentHunk != h { editor.selectHunk(h) }
        if isDouble, pt.x < leftWidth, !editor.state.isEditing { editor.beginEditing() }
    }

    func doubleClick(_ i: Int, _ layout: MergePaneLayout) {
        guard clicks.lastWasLeft(row: i), let h = layout.rows[i].hunk, !editor.state.isEditing else { return }
        editor.selectHunk(h)
        editor.beginEditing()
    }

    func token(_ h: Int, _ t: ConflictEditorState.Token) -> some View {
        Menu {
            ForEach(Array(MergeSheetText.chooseTitles.enumerated()), id: \.offset) { pair in
                Button(pair.element) { editor.choose(MergeSheetText.chooseChoices[pair.offset], forHunk: h) }
                    .onAppear { if pair.offset == 0, editor.state.currentHunk != h { editor.selectHunk(h) } }
                if pair.offset == MergeSheetText.chooseSeparatorAfter { Divider() }
            }
        } label: {
            MergeTokenView(token: t, palette: palette)
        }
        .menuStyle(.borderlessButton)
        #if !os(Linux)
        .menuIndicator(.hidden)
        #endif
        .fixedSize()
        .simultaneousGesture(TapGesture().onEnded { if editor.state.currentHunk != h { editor.selectHunk(h) } })
        .shellTarget("merge token \(h)")
    }

    func handEditor(_ p: MergeSheetPalette) -> some View {
        TextEditor(text: Binding(get: { editor.editedText }, set: { editor.editedText = $0 }))
            .font(ShellFonts.editor(MergeCodeFont.size))
            .scrollContentBackground(.hidden)
            .background(Color(mergeHex: p.sheet))
            .overlay { Rectangle().stroke(Color(mergeHex: p.selectedRule), lineWidth: 1) }
            .shellTarget("merge hand editor")
    }
}

final class MergeClickTracker {
    private var last: (row: Int, time: Date, left: Bool)?

    func isDouble(row: Int, left: Bool) -> Bool {
        let now = Date()
        defer { last = (row, now, left) }
        guard let l = last, l.row == row else { return false }
        return now.timeIntervalSince(l.time) < 0.4
    }

    func lastWasLeft(row: Int) -> Bool { last.map { $0.row == row && $0.left } ?? false }
}

final class MergeLayoutCache {
    private var key: (doc: MergeDocument?, file: String, left: CGFloat, right: CGFloat, palette: MergeSheetPalette)?
    private var cached: MergePaneLayout?

    @MainActor
    func layout(state: ConflictEditorState, fileName: String, leftWidth: CGFloat, rightWidth: CGFloat, palette: MergeSheetPalette) -> MergePaneLayout {
        if let k = key, let c = cached, k.doc == state.document, k.file == fileName, k.left == leftWidth, k.right == rightWidth, k.palette == palette {
            return c
        }
        let l = MergePaneLayout(state: state, fileName: fileName, leftWidth: leftWidth, rightWidth: rightWidth, palette: palette,
                                theme: SourcePalette.forAppearance(dark: palette == .dark, theme: Preferences.shared.theme))
        key = (state.document, fileName, leftWidth, rightWidth, palette)
        cached = l
        return l
    }
}

struct MergePaneLayout {
    let rows: [MergeSheetRow]
    let heights: [CGFloat]
    let tops: [CGFloat]
    let leftRuns: [[(text: String, role: SyntaxTokenKind.Role?)]]
    let rightRuns: [[(text: String, role: SyntaxTokenKind.Role?)]]
    let leftWidth: CGFloat
    let rightWidth: CGFloat
    let columns: Int
    let palette: MergeSheetPalette
    let theme: SourcePalette

    typealias M = MergeSheetMetrics

    init(state: ConflictEditorState, fileName: String, leftWidth: CGFloat, rightWidth: CGFloat, palette: MergeSheetPalette, theme: SourcePalette) {
        rows = state.sheetRows
        leftRuns = MergeSheetLayout.highlight(state.leftLines, fileName: fileName)
        rightRuns = MergeSheetLayout.highlight(state.rightLines, fileName: fileName)
        self.leftWidth = leftWidth
        self.rightWidth = rightWidth
        self.palette = palette
        self.theme = theme
        let cols = M.columnsOfText(paneWidth: Double(leftWidth))
        columns = cols
        heights = rows.map { CGFloat(MergeSheetLayout.height($0, columns: cols)) }
        var y: CGFloat = 0
        tops = heights.map { h in
            defer { y += h }
            return y
        }
    }

    var gutterX: CGFloat { leftWidth + 1 }
    var rightX: CGFloat { leftWidth + 1 + CGFloat(M.gutterWidth) + 1 }
    var totalWidth: CGFloat { rightX + rightWidth }

    func rows(ofHunk h: Int) -> Range<Int>? {
        guard let a = rows.firstIndex(where: { $0.hunk == h }), let b = rows.lastIndex(where: { $0.hunk == h }) else { return nil }
        return a..<(b + 1)
    }
}

enum MergeCodeFont {
    nonisolated(unsafe) static var measured: CGFloat?

    static var size: CGFloat { measured ?? 13 }

    static func font(_ ctx: GraphicsContext) -> Font {
        if measured == nil {
            let probe = String(repeating: "M", count: 40)
            let w = ctx.resolve(Text(verbatim: probe).font(ShellFonts.editor(13))).measure(in: CGSize(width: CGFloat.infinity, height: .infinity)).width / 40
            measured = w > 1 ? min(16, max(10, 13 * CGFloat(MergeSheetMetrics.cellWidth) / w)) : 13
        }
        return ShellFonts.editor(size)
    }
}

struct MergeRowPainter {
    let row: MergeSheetRow
    let layout: MergePaneLayout
    let currentLeft: Int
    let currentRight: Int
    let isSelected: Bool
    let isDecided: Bool

    typealias M = MergeSheetMetrics

    func draw(_ ctx: inout GraphicsContext) {
        let p = layout.palette
        let lw = layout.leftWidth, rw = layout.rightWidth, rx = layout.rightX, gx = layout.gutterX
        let h = CGFloat(MergeSheetLayout.height(row, columns: layout.columns))
        let lh = CGFloat(M.lineHeight)
        func fill(_ r: CGRect, _ hex: UInt32) { ctx.fill(Path(r), with: .color(Color(mergeHex: hex))) }
        fill(CGRect(x: 0, y: 0, width: lw, height: h), p.sheet)
        fill(CGRect(x: rx, y: 0, width: rw, height: h), p.sheet)
        fill(CGRect(x: gx, y: 0, width: CGFloat(M.gutterWidth), height: h), p.gutter)
        if row.kind != .same {
            let shade = row.kind == .conflict ? p.conflictRow : p.cleanRow
            fill(CGRect(x: 0, y: 0, width: lw, height: h), shade)
            fill(CGRect(x: rx, y: 0, width: rw, height: h), shade)
            fill(CGRect(x: gx, y: 0, width: CGFloat(M.gutterWidth), height: h), row.kind == .conflict ? p.gutterConflict : p.gutterClean)
        } else {
            let inset = CGFloat(M.currentLineInset)
            if let l = row.left, l.number == currentLeft {
                let n = CGFloat(MergeSheetLayout.wrap(l.text, columns: layout.columns).count)
                ctx.fill(Path(roundedRect: CGRect(x: inset, y: 0, width: lw - 2 * inset, height: n * lh), cornerRadius: 4), with: .color(Color(mergeHex: p.currentLine)))
            }
            if let r = row.right, r.number == currentRight {
                let n = CGFloat(MergeSheetLayout.wrap(r.text, columns: layout.columns).count)
                ctx.fill(Path(roundedRect: CGRect(x: rx + inset, y: 0, width: rw - 2 * inset, height: n * lh), cornerRadius: 4),
                         with: .color(Color(mergeHex: p.currentLine)))
            }
        }
        fill(CGRect(x: lw, y: 0, width: 1, height: h), p.columnRule)
        fill(CGRect(x: rx - 1, y: 0, width: 1, height: h), p.columnRule)
        let font = MergeCodeFont.font(ctx)
        if let l = row.left { side(&ctx, l, runs: layout.leftRuns, x: 0, current: currentLeft, font: font) }
        if let r = row.right { side(&ctx, r, runs: layout.rightRuns, x: rx, current: currentRight, font: font) }
        if isSelected {
            let rule = isDecided ? p.decidedRule : p.selectedRule
            if row.isFirstOfHunk { fill(CGRect(x: 0, y: 0, width: layout.totalWidth, height: 1), rule) }
            if row.isLastOfHunk { fill(CGRect(x: 0, y: h - 1, width: layout.totalWidth, height: 1), rule) }
        }
    }

    func side(_ ctx: inout GraphicsContext, _ s: MergeSheetRow.Side, runs: [[(text: String, role: SyntaxTokenKind.Role?)]], x: CGFloat,
              current: Int, font: Font) {
        let p = layout.palette
        let lh = CGFloat(M.lineHeight), cw = CGFloat(M.cellWidth)
        let segs = MergeSheetLayout.wrap(s.text, columns: layout.columns)
        for (k, seg) in segs.enumerated() {
            for w in s.words {
                let a = max(w.lowerBound, seg.cells.lowerBound), b = min(w.upperBound, seg.cells.upperBound)
                guard a < b else { continue }
                ctx.fill(Path(CGRect(x: x + CGFloat(M.codeX) + CGFloat(seg.column + a - seg.cells.lowerBound) * cw,
                                     y: CGFloat(k) * lh + CGFloat(M.wordInset), width: CGFloat(b - a) * cw, height: lh - 2 * CGFloat(M.wordInset))),
                         with: .color(Color(mergeHex: p.conflictWord)))
            }
        }
        let numberColor = Color(mergeHex: s.number == current ? p.currentLineNumber : p.lineNumber)
        ctx.draw(Text(verbatim: String(s.number)).font(Font.system(size: 10).monospacedDigit()).foregroundStyle(numberColor),
                 at: CGPoint(x: x + CGFloat(M.lineNumberRight), y: lh / 2), anchor: .trailing)
        let line = runs.indices.contains(s.number - 1) ? runs[s.number - 1] : [(s.text, nil)]
        for (k, seg) in segs.enumerated() {
            var pieces: [Text] = []
            var at = 0
            for run in line {
                let chars = Array(run.text)
                let a = max(seg.cells.lowerBound, at), b = min(seg.cells.upperBound, at + chars.count)
                if a < b {
                    let piece = Text(verbatim: String(chars[(a - at)..<(b - at)])).foregroundStyle(layout.theme.color(run.role).color)
                    pieces.append(run.role == .keyword ? piece.bold() : piece)
                }
                at += chars.count
            }
            let t = pieces.reduce(Text(verbatim: ""), +)
            ctx.draw(t.font(font), at: CGPoint(x: x + CGFloat(M.codeX) + CGFloat(seg.column) * cw, y: CGFloat(k) * lh + lh / 2), anchor: .leading)
        }
    }
}

struct MergeTokenView: View {
    var token: ConflictEditorState.Token
    var palette: MergeSheetPalette

    typealias M = MergeSheetMetrics

    var body: some View {
        let p = palette
        let w = CGFloat(M.tokenWidth), h = CGFloat(M.tokenHeight)
        ZStack(alignment: .topLeading) {
            Capsule(style: .continuous).fill(Color(mergeHex: token.isSelected ? p.selectedToken : p.token))
            if token.isSelected {
                Capsule(style: .continuous).strokeBorder(Color(mergeHex: p.selectedTokenRim), lineWidth: 1)
            }
            Text(verbatim: token.glyph).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(mergeHex: p.tokenInk))
                .frame(width: 14, height: h)
                .offset(x: 21.5 - 7)
            if token.isDecided {
                Circle().fill(Color(mergeHex: token.isSelected ? p.selectedChevronCircle : p.chevronCircle))
                    .frame(width: CGFloat(M.chevronCircle), height: CGFloat(M.chevronCircle))
                    .offset(x: 33.5 - CGFloat(M.chevronCircle) / 2, y: (h - CGFloat(M.chevronCircle)) / 2)
            }
            Path { path in
                path.move(to: CGPoint(x: 30.5, y: h / 2 - 1.5))
                path.addLine(to: CGPoint(x: 33.5, y: h / 2 + 1.75))
                path.addLine(to: CGPoint(x: 36.5, y: h / 2 - 1.5))
            }
            .stroke(Color(mergeHex: p.tokenInk), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(width: w, height: h)
        .contentShape(Capsule())
    }
}

struct MergeRuler: View {
    var marks: [(position: Double, isConflict: Bool)]
    var palette: MergeSheetPalette
    var onClick: (Double) -> Void

    var body: some View {
        let p = palette
        GeometryReader { geo in
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(mergeHex: p.sheet)))
                for m in marks {
                    ctx.fill(Path(CGRect(x: CGFloat(MergeSheetMetrics.rulerMarkX), y: (CGFloat(m.position) * size.height).rounded(.down),
                                         width: CGFloat(MergeSheetMetrics.rulerMarkWidth), height: 1)),
                             with: .color(Color(mergeHex: m.isConflict ? p.rulerConflict : p.rulerClean)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 1, coordinateSpace: .local) { pt in onClick(max(0, min(1, Double(pt.y / max(1, geo.size.height))))) }
        }
    }
}
