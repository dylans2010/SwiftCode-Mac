import Foundation

@MainActor
package protocol AnimationTimeSource: AnyObject {
    var now: TimeInterval { get }
}

@MainActor
package final class ManualAnimationClock: AnimationTimeSource {
    package let framesPerSecond: Double
    package private(set) var frame = 0
    private var offset: TimeInterval = 0

    package init(framesPerSecond: Double = 60) { self.framesPerSecond = framesPerSecond }

    package var now: TimeInterval { offset + Double(frame) / framesPerSecond }
    package var frameDuration: TimeInterval { 1 / framesPerSecond }

    package func advance(frames: Int = 1) { frame += frames }

    package func advance(by seconds: TimeInterval) { offset += seconds }
}

@MainActor
package protocol AnimationDriver: AnyObject {
    func sample(at time: TimeInterval) -> Bool
    var isActive: Bool { get }
    var owner: ViewNode? { get }
    var onChange: (() -> Void)? { get }
    func cancel()
    var runStart: TimeInterval? { get }
}

extension AnimationDriver {
    package var runStart: TimeInterval? { nil }
}

package final class AnimationCompletionRecord: @unchecked Sendable {
    package let criteria: AnimationCompletionCriteria
    package let action: () -> Void
    private var pendingLogical = 0
    private var pendingRemoved = 0
    private var sealed = false
    private var fired = false
    private weak var graph: ViewGraph?

    package init(criteria: AnimationCompletionCriteria, action: @escaping () -> Void) {
        self.criteria = criteria
        self.action = action
    }

    @MainActor package func register(graph: ViewGraph) {
        self.graph = graph
        pendingLogical += 1
        pendingRemoved += 1
    }

    @MainActor package func runLogicallyCompleted() {
        pendingLogical -= 1
        check()
    }

    @MainActor package func runRemoved(wasLogicallyComplete: Bool) {
        if !wasLogicallyComplete { pendingLogical -= 1 }
        pendingRemoved -= 1
        check()
    }

    @MainActor package func seal(graph: ViewGraph) {
        if self.graph == nil { self.graph = graph }
        guard !sealed else { return }
        sealed = true
        check()
    }

    @MainActor private func check() {
        guard sealed, !fired, let graph else { return }
        let done = criteria == .removed ? pendingRemoved <= 0 : pendingLogical <= 0
        if done {
            fired = true
            graph.queueCompletion(action)
        }
    }
}

@MainActor
package final class Animator<V: VectorArithmetic>: AnimationDriver {
    private struct Run {
        var animation: Animation
        var from: V
        var delta: V
        var begin: TimeInterval
        var context: AnimationContext<V>
        var records: [AnimationCompletionRecord]
        var logicallyComplete = false
    }

    package private(set) var model: V
    package private(set) var presented: V
    package weak var owner: ViewNode?
    package var onChange: (() -> Void)?
    private var run: Run?
    private var lastTime: TimeInterval = 0

    package init(_ value: V, owner: ViewNode?) {
        model = value
        presented = value
        self.owner = owner
    }

    package var isActive: Bool { run != nil }

    package var runStart: TimeInterval? { run?.begin }

    package var animation: Animation? { run?.animation }

    package func update(to value: V, transaction: Transaction, graph: ViewGraph) {
        update(to: value, animation: transaction.animation, completions: transaction.completions, graph: graph)
    }

    package func update(to value: V, animation: Animation?, completions: [AnimationCompletionRecord] = [],
                        graph: ViewGraph) {
        guard value != model else { return }
        guard let animation else {
            let shift = value - model
            model = value
            presented += shift
            run?.from += shift
            return
        }
        let now = graph.currentTime
        var context = AnimationContext<V>(environment: owner?.environment ?? EnvironmentValues())
        if let old = run {
            var oldContext = old.context
            if animation.shouldMerge(previous: old.animation, value: old.delta, time: now - old.begin, context: &oldContext) {
                context.state = oldContext.state
            }
            finish(old)
        }
        for r in completions { r.register(graph: graph) }
        model = value
        run = Run(animation: animation, from: presented, delta: value - presented, begin: now,
                  context: context, records: completions)
        lastTime = now
        graph.activate(self)
    }

    package var velocity: V {
        guard let r = run else { return .zero }
        return r.animation.velocity(value: r.delta, time: lastTime - r.begin, context: r.context) ?? .zero
    }

    package func sample(at time: TimeInterval) -> Bool {
        guard var r = run else { return false }
        lastTime = time
        let old = presented
        if let offset = r.animation.animate(value: r.delta, time: max(0, time - r.begin), context: &r.context) {
            presented = r.from + offset
            if r.context.isLogicallyComplete && !r.logicallyComplete {
                r.logicallyComplete = true
                for c in r.records { c.runLogicallyCompleted() }
            }
            run = r
        } else {
            presented = model
            run = nil
            finish(r)
        }
        return presented != old
    }

    package func cancel() { stop() }

    package func stop() {
        guard let r = run else { return }
        run = nil
        presented = model
        finish(r)
    }

    private func finish(_ r: Run) {
        for c in r.records { c.runRemoved(wasLogicallyComplete: r.logicallyComplete) }
    }
}

@MainActor
package final class FrameDriver: AnimationDriver {
    package weak var owner: ViewNode?
    package var onChange: (() -> Void)?
    private let step: (TimeInterval) -> (changed: Bool, active: Bool)
    package private(set) var isActive = true

    package init(owner: ViewNode?, step: @escaping (TimeInterval) -> (changed: Bool, active: Bool)) {
        self.owner = owner
        self.step = step
    }

    package func sample(at time: TimeInterval) -> Bool {
        guard isActive else { return false }
        let r = step(time)
        isActive = r.active
        return r.changed
    }

    package func cancel() { isActive = false }
}
