import Foundation
import SwiftUI
import SwiftCodeIDEShell
#if os(Linux)
import OVPlatform
#endif

@MainActor
enum DebugGutter {
    static func connect(_ c: SourceEditorController, model: WorkspaceShellModel) {
        let path = c.document.path
        c.onGutterClick = { [weak model] line in model?.debug.gutterClick(file: path, line: line) }
        c.onGutterDrag = { [weak model] from, to in model?.debug.gutterDrag(file: path, from: from, to: to) }
        c.hasBreakpoint = { [weak model] line in model?.debug.breakpoints.breakpoint(file: path, line: line) != nil }
        c.onGutterDoubleClick = { [weak model, weak c] line in
            guard let model, let c else { return }
            model.debug.editBreakpoint(file: path, line: line, anchor: anchor(c, line: line))
        }
    }

    static func anchor(_ c: SourceEditorController, line: Int) -> CGRect {
        CGRect(x: c.windowOrigin.x, y: c.windowOrigin.y + c.lineTop(line - 1) - c.top, width: c.gutterWidth - 4, height: c.lineHeight)
    }

    static func hover(_ phase: HoverPhase, controller c: SourceEditorController, model: WorkspaceShellModel) {
        switch phase {
        case .active(let p): model.debug.pointerInGutter(file: c.document.path, line: p.x < c.gutterWidth ? c.lineNumber(at: p) : nil)
        case .ended: model.debug.pointerInGutter(file: c.document.path, line: nil)
        }
    }

    #if os(Linux)
    static func commandClick(_ p: CGPoint, modifiers m: KeyModifiers, controller c: SourceEditorController, model: WorkspaceShellModel) -> Bool {
        guard m.contains(.command), p.x < c.gutterWidth, let line = c.lineNumber(at: p),
              model.debug.breakpoints.breakpoint(file: c.document.path, line: line) != nil else { return false }
        model.debug.editBreakpoint(file: c.document.path, line: line, anchor: anchor(c, line: line))
        return true
    }
    #endif

    @discardableResult
    static func drawBreakpoint(_ ctx: inout GraphicsContext, _ m: EditorDebugMarks, line: Int, top: CGFloat, lineHeight: CGFloat,
                               numberRight: CGFloat) -> Bool {
        guard let b = m.breakpoints[line] else { return false }
        let r = CGRect(x: 2, y: top + 1, width: numberRight + 7 - 2, height: lineHeight - 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 6, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - 6, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        let base = b.isCustomized ? Color(.sRGB, red: 0, green: 80 / 255, blue: 166 / 255) : DebugColors.breakpoint
        ctx.fill(p, with: .color(base.opacity(b.isEnabled && m.breakpointsActive ? 1 : 0.35)))
        return true
    }

    static func drawStoppedLine(_ ctx: inout GraphicsContext, _ m: EditorDebugMarks, lines: Range<Int>, top: (Int) -> CGFloat,
                                lineHeight: CGFloat, width: CGFloat) {
        guard let pc = m.pcLine, lines.contains(pc - 1) else { return }
        ctx.fill(Path(CGRect(x: 0, y: top(pc - 1), width: width, height: lineHeight)), with: .color(DebugColors.pcLine.opacity(0.25)))
    }

    static func drawPCMark(_ ctx: inout GraphicsContext, _ m: EditorDebugMarks, line: Int, top: CGFloat, lineHeight: CGFloat) {
        guard m.pcLine == line else { return }
        ctx.fill(Path(CGRect(x: 0, y: top, width: 3, height: lineHeight)), with: .color(DebugColors.pcLine.opacity(0.9)))
    }

    static func drawAnnotation(_ ctx: inout GraphicsContext, _ m: EditorDebugMarks, lines: Range<Int>, top: (Int) -> CGFloat,
                               lineHeight: CGFloat, width: CGFloat) {
        guard let pc = m.pcLine, let text = m.annotation, lines.contains(pc - 1) else { return }
        let label = ctx.resolve(Text(verbatim: text).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.white))
        let size = label.measure(in: CGSize(width: width * 0.6, height: lineHeight))
        let w = min(size.width, width * 0.6) + 12
        let box = CGRect(x: max(width - w - 14, 200), y: top(pc - 1) + 0.5, width: w, height: lineHeight - 1)
        ctx.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(DebugColors.pcLine.opacity(0.85)))
        ctx.draw(label, in: CGRect(x: box.minX + 6, y: box.minY + (box.height - size.height) / 2, width: w - 12, height: size.height))
    }
}
