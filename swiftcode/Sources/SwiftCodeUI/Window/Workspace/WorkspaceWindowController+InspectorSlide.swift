import AppKit
import QuartzCore
import SwiftCodeIDECore

extension WorkspaceWindowController {
    @objc public func toggleInspector(_ sender: Any?) {
        slideInspector(show: inspectorItem.isCollapsed)
    }

    public var isInspectorSliding: Bool { inspectorSlide.link != nil }

    func slideInspector(show: Bool) {
        let split = mainSplit.splitView
        guard let window, window.isVisible, inspectorSlide.link == nil, split.subviews.count >= 3 else {
            if inspectorSlide.link == nil { inspectorItem.isCollapsed = !show }
            return
        }
        guard show == inspectorItem.isCollapsed else { return }
        let state = inspectorSlide
        state.minimum = inspectorItem.minimumThickness
        let total = split.bounds.width
        let divider = split.dividerThickness
        let width: CGFloat
        if show {
            width = max(inspectorItem.minimumThickness, state.lastWidth ?? Self.inspectorWidth)
            inspectorItem.minimumThickness = 1
            inspectorItem.isCollapsed = false
            split.setPosition(total - divider - 1, ofDividerAt: 1)
        } else {
            width = inspector.view.frame.width
            state.lastWidth = width
            inspectorItem.minimumThickness = 1
        }
        inspector.beginRigidSlide(width: width)
        inspector.view.layoutSubtreeIfNeeded()
        inspector.view.displayIfNeeded()
        state.from = show ? total - divider - 1 : total - divider - width
        state.to = show ? total - divider - width : total - divider - 1
        state.show = show
        state.start = nil
        let link = split.displayLink(target: state, selector: #selector(InspectorSlideState.step(_:)))
        state.onFrame = { [weak self] progress in self?.inspectorSlideFrame(progress) }
        link.add(to: .main, forMode: .common)
        state.link = link
    }

    private func inspectorSlideFrame(_ progress: CGFloat) {
        let state = inspectorSlide
        let split = mainSplit.splitView
        let x = (state.from + (state.to - state.from) * progress).rounded()
        split.setPosition(x, ofDividerAt: 1)
        guard progress >= 1 else { return }
        state.link?.invalidate()
        state.link = nil
        inspector.endRigidSlide()
        if !state.show { inspectorItem.isCollapsed = true }
        inspectorItem.minimumThickness = state.minimum
        updateToolbarState()
    }

    var inspectorSlide: InspectorSlideState { inspectorSlideBox }
}

@MainActor
final class InspectorSlideState: NSObject {
    var link: CADisplayLink?
    var start: CFTimeInterval?
    var from: CGFloat = 0
    var to: CGFloat = 0
    var show = false
    var minimum: CGFloat = 0
    var lastWidth: CGFloat?
    var onFrame: ((CGFloat) -> Void)?

    static let duration = EditorMetrics.inspectorSlideDuration

    @objc func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        guard let start else { start = now; onFrame?(0); return }
        let elapsed = now - start
        let progress = elapsed >= EditorMetrics.inspectorSlideTotal(show: show) ? 1
            : EditorMetrics.inspectorSlideProgress(elapsed: elapsed, show: show)
        onFrame?(CGFloat(progress))
    }
}
