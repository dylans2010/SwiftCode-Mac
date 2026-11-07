import AppKit
import YcodeIDECore
import YcodeLanguage

@MainActor
final class CompletionPopupView: NSView {
    var model = CompletionModel() { didSet { keepSelectionVisible(); needsDisplay = true } }
    var onAccept: (() -> Void)?
    static let rowHeight: CGFloat = 20
    static let maxRows = 8
    static let docHeight: CGFloat = 22
    static let padding: CGFloat = 3
    private(set) var firstVisible = 0

    static func height(rows: Int, hasDoc: Bool) -> CGFloat {
        CGFloat(min(rows, maxRows)) * rowHeight + 2 * padding + (hasDoc ? docHeight : 0)
    }

    var hasDoc: Bool { !(model.current?.documentation ?? "").isEmpty }

    override var isFlipped: Bool { true }

    private func keepSelectionVisible() {
        if model.selected < firstVisible { firstVisible = model.selected }
        if model.selected >= firstVisible + Self.maxRows { firstVisible = model.selected - Self.maxRows + 1 }
        firstVisible = max(0, min(firstVisible, max(0, model.visible.count - Self.maxRows)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.stroke()
        let end = min(model.visible.count, firstVisible + Self.maxRows)
        for i in firstVisible..<max(firstVisible, end) {
            let row = NSRect(x: 2, y: Self.padding + CGFloat(i - firstVisible) * Self.rowHeight, width: bounds.width - 4, height: Self.rowHeight)
            let selected = i == model.selected
            if selected {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: row, xRadius: 4, yRadius: 4).fill()
            }
            let item = model.visible[i]
            let s = NSMutableAttributedString(string: Self.kindLetter(item.kind) + "  ", attributes: [
                .font: Theme.boldFont, .foregroundColor: selected ? NSColor.white : NSColor.systemPurple])
            s.append(NSAttributedString(string: item.label, attributes: [
                .font: Theme.font, .foregroundColor: selected ? NSColor.white : NSColor.labelColor]))
            if let d = item.detail {
                s.append(NSAttributedString(string: "  " + d, attributes: [
                    .font: Theme.font, .foregroundColor: selected ? NSColor.white.withAlphaComponent(0.8) : NSColor.secondaryLabelColor]))
            }
            let h = s.size().height
            s.draw(with: NSRect(x: row.minX + 6, y: row.midY - h / 2, width: row.width - 12, height: h),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        if hasDoc, let doc = model.current?.documentation {
            let top = bounds.height - Self.docHeight
            NSColor.separatorColor.setFill()
            NSRect(x: 0, y: top, width: bounds.width, height: 1).fill()
            let text = NSAttributedString(string: doc.replacingOccurrences(of: "\n", with: " "), attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
            let h = text.size().height
            text.draw(with: NSRect(x: 8, y: top + (Self.docHeight - h) / 2, width: bounds.width - 16, height: h),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    func row(at p: NSPoint) -> Int? {
        let i = firstVisible + Int(floor((p.y - Self.padding) / Self.rowHeight))
        return p.y >= Self.padding && i < min(model.visible.count, firstVisible + Self.maxRows) ? i : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let i = row(at: convert(event.locationInWindow, from: nil)) else { return }
        model.selected = i
        if event.clickCount >= 2 { onAccept?() }
    }

    override func scrollWheel(with event: NSEvent) {
        let step = event.scrollingDeltaY > 0 ? -1 : (event.scrollingDeltaY < 0 ? 1 : 0)
        firstVisible = max(0, min(firstVisible + step, max(0, model.visible.count - Self.maxRows)))
        needsDisplay = true
    }

    static func kindLetter(_ kind: Int?) -> String {
        switch kind {
        case 2, 3, 4: "M"
        case 5, 10: "P"
        case 6: "V"
        case 7: "C"
        case 8: "R"
        case 9: "K"
        case 13: "E"
        case 14: "K"
        case 20: "e"
        case 22: "S"
        default: "·"
        }
    }
}
