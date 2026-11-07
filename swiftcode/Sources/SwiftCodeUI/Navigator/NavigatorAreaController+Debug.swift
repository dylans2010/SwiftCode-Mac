import AppKit
import SwiftCodeDebug
import SwiftCodeIDECore

extension NavigatorAreaController {
    public func setDebugProcess(_ p: DebugProcessInfo?) {
        guard p != debugProcess else { return }
        debugProcess = p
        let s = lastDebugState
        setDebugState(threads: s.0, stoppedThread: s.1, frames: s.2)
    }

    @objc func debugViewOptionChosen(_ item: NSMenuItem) {
        if item.tag == 0 { showThreadsByQueue.toggle() } else { showsGauges.toggle() }
        refreshDebugTree()
        rebuildFilterOptionsMenu()
    }

    func refreshDebugTree() {
        let s = lastDebugState
        setDebugState(threads: s.0, stoppedThread: s.1, frames: s.2)
    }

    func addEnabledMarker(_ on: Bool, to cell: NSView) {
        let m = NSImageView(image: NSImage(systemSymbolName: on ? "tag.fill" : "tag", accessibilityDescription: on ? "Enabled" : "Disabled")!)
        m.contentTintColor = on ? Theme.breakpointColor : .tertiaryLabelColor
        m.toolTip = "Click to enable or disable the breakpoint"
        m.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(m)
        NSLayoutConstraint.activate([
            m.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            m.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }
}

extension NavigatorAreaController {
    func addLevelBar(_ level: Double, to cell: NSView) {
        let bar = NSLevelIndicator()
        bar.levelIndicatorStyle = .continuousCapacity
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = level
        bar.toolTip = "Energy Impact"
        bar.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -70),
            bar.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            bar.widthAnchor.constraint(equalToConstant: 44),
            bar.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    func addRowButtons(_ list: [(symbol: String, toolTip: String, action: String)], to cell: NSView) {
        let stack = NSStackView()
        stack.spacing = 2
        for b in list {
            let button = NSButton(image: NSImage(systemSymbolName: b.symbol, accessibilityDescription: b.toolTip)!, target: nil,
                                  action: NSSelectorFromString(b.action))
            button.isBordered = false
            button.toolTip = b.toolTip
            button.contentTintColor = .secondaryLabelColor
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
    }

    public var debugThreadRows: [OutlineItem] {
        let r = rows(6)
        guard debugProcess != nil, let root = r.first else { return r }
        return root.children.filter { $0.badge == nil }
    }

    public var breakpointGroups: [OutlineItem] { rows(7).first?.children ?? [] }
}
