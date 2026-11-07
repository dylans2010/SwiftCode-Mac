import AppKit
import QuartzCore
import SwiftCodeIDECore

final class EditorScrollView: NSScrollView {
    let topBounce = EditorTopBounce()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = EditorClipView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func scrollWheel(with event: NSEvent) {
        if topBounce.handle(event, in: self) { return }
        if scrollByLineWheel(event) { return }
        let before = contentView.bounds.origin
        super.scrollWheel(with: event)
        followFirstEvent(event, from: before)
    }

    func followFirstEvent(_ event: NSEvent, from before: NSPoint) {
        guard event.phase.contains(.began), event.momentumPhase.isEmpty, event.hasPreciseScrollingDeltas,
              contentView.bounds.origin == before else { return }
        let dy = event.scrollingDeltaY, dx = hasHorizontalScroller ? event.scrollingDeltaX : 0
        guard dx != 0 || dy != 0 else { return }
        let clip = contentView
        var origin = clip.bounds.origin
        origin.x -= dx
        origin.y += clip.isFlipped ? -dy : dy
        let kept = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin
        guard kept != clip.bounds.origin else { return }
        clip.scroll(to: kept)
        reflectScrolledClipView(clip)
    }

    func scrollByLineWheel(_ event: NSEvent) -> Bool {
        guard let delta = Self.pointDelta(of: event) else { return false }
        let clip = contentView
        var origin = clip.bounds.origin
        origin.x -= delta.width
        origin.y += clip.isFlipped ? -delta.height : delta.height
        let kept = clip.constrainBoundsRect(NSRect(origin: origin, size: clip.bounds.size)).origin
        if kept != clip.bounds.origin {
            clip.scroll(to: kept)
            reflectScrolledClipView(clip)
        }
        return true
    }

    static func pointDelta(of event: NSEvent) -> CGSize? {
        guard event.type == .scrollWheel, !event.hasPreciseScrollingDeltas, event.phase.isEmpty, event.momentumPhase.isEmpty,
              let cg = event.cgEvent else { return nil }
        let dy = cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let dx = cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        guard dx != 0 || dy != 0 else { return nil }
        return CGSize(width: dx, height: dy)
    }
}

@MainActor
final class EditorTopBounce: NSObject {
    private var tracker = TopBounce.VelocityTracker()
    private var gestureVelocity = 0.0
    private var startOverscroll = 0.0
    private(set) var velocity: Double?
    private var start: CFTimeInterval?
    private var link: CADisplayLink?
    private var timer: Timer?
    private weak var scrollView: NSScrollView?
    private var swallowingMomentum = false
    private var heldEnd: NSEvent?
    private(set) var lastPeak: CGFloat = 0
    var onFrame: ((CGFloat) -> Void)?

    var isRunning: Bool { velocity != nil }

    static func top(of scrollView: NSScrollView) -> CGFloat { -scrollView.contentInsets.top }

    var isEnabled = true

    func handle(_ event: NSEvent, in scrollView: NSScrollView) -> Bool {
        guard isEnabled else { return false }
        let momentum = event.momentumPhase
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            if isRunning { finish(at: nil) }
            swallowingMomentum = false
            heldEnd = nil
            tracker.reset()
        }
        if swallowingMomentum, !momentum.isEmpty {
            if momentum.contains(.ended) || momentum.contains(.cancelled) {
                swallowingMomentum = false
                if isRunning { heldEnd = event; return true }
                return false
            }
            return true
        }
        guard event.hasPreciseScrollingDeltas else { return false }
        let delta = Double(event.scrollingDeltaY)
        if momentum.contains(.began) {
            gestureVelocity = tracker.velocity
            tracker.reset()
        }
        tracker.add(delta, at: event.timestamp)
        guard momentum.contains(.began) || momentum.contains(.changed), delta > 0 else { return false }
        let clip = scrollView.contentView
        let top = Self.top(of: scrollView)
        guard clip.bounds.minY - CGFloat(delta) < top else { return false }
        let v = tracker.hasSample ? tracker.velocity : max(gestureVelocity, delta / 0.0167)
        begin(velocity: v, from: max(0, top - clip.bounds.minY), in: scrollView)
        return true
    }

    func begin(velocity v: Double, from overscroll: CGFloat = 0, in scrollView: NSScrollView) {
        self.scrollView = scrollView
        let visible = Double(scrollView.contentView.bounds.height - scrollView.contentInsets.top - scrollView.contentInsets.bottom)
        velocity = TopBounce.effectiveVelocity(v, visibleHeight: visible)
        startOverscroll = Double(overscroll)
        lastPeak = overscroll
        swallowingMomentum = true
        start = nil
        set(overscroll: overscroll)
        link?.invalidate()
        timer?.invalidate()
        if scrollView.window?.isVisible == true, scrollView.window?.screen != nil {
            let l = scrollView.displayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        } else {
            let interval = 1.0 / 120
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advance(to: CACurrentMediaTime(), frame: interval) }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        advance(to: link.targetTimestamp, frame: link.duration)
    }

    private func advance(to now: CFTimeInterval, frame: CFTimeInterval) {
        guard let v = velocity else { return }
        if start == nil { start = now - frame }
        let t = now - (start ?? now)
        let x = CGFloat(TopBounce.overscroll(from: startOverscroll, velocity: v, at: t))
        if TopBounce.isAtRest(from: startOverscroll, velocity: v, at: t) {
            finish(at: 0)
            return
        }
        lastPeak = max(lastPeak, x)
        set(overscroll: x)
    }

    private func finish(at overscroll: CGFloat?) {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
        velocity = nil
        start = nil
        if let overscroll { set(overscroll: overscroll) }
        if let end = heldEnd, let scrollView {
            heldEnd = nil
            (scrollView as? EditorScrollView)?.superScrollWheel(end)
        }
    }

    private func set(overscroll x: CGFloat) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        (clip as? EditorClipView)?.allowedOverscroll = x
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.minX, y: Self.top(of: scrollView) - x))
        scrollView.reflectScrolledClipView(clip)
        onFrame?(x)
    }
}

final class EditorClipView: NSClipView {
    var allowedOverscroll: CGFloat = 0

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        if allowedOverscroll > 0, proposedBounds.minY < r.minY {
            r.origin.y = max(proposedBounds.minY, r.minY - allowedOverscroll)
        }
        return r
    }
}

extension EditorScrollView {
    func superScrollWheel(_ event: NSEvent) { super.scrollWheel(with: event) }
}
