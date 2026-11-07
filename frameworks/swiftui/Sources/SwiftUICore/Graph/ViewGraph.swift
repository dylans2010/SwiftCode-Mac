import Foundation

package struct HostLayout {
    package enum Mode {
        case window(CGSize, safeAreaInsets: EdgeInsets)
        case proposal(ProposedViewSize)
    }
    package var mode: Mode
    package var textMeasurer: any TextMeasurer
    package var symbols: any SymbolProvider

    package init(_ mode: Mode, textMeasurer: any TextMeasurer = TypesetTextMeasurer.shared,
                 symbols: any SymbolProvider = StubSymbolProvider()) {
        self.mode = mode
        self.textMeasurer = textMeasurer
        self.symbols = symbols
    }
}

@MainActor
package final class ViewGraph {
    private var rootView: any View
    private var rootViewChanged = true
    package private(set) var root: ViewNode?

    package var environment: EnvironmentValues {
        didSet { if environment.revision != oldValue.revision { needsUpdate = true } }
    }

    package var layout: HostLayout? { didSet { needsUpdate = true } }
    package private(set) var layoutResult: LayoutResult?

    package private(set) var rootPreferences = PreferenceValues()

    package private(set) var needsUpdate = true
    private var pendingTransaction: Transaction?
    package private(set) var passCount = 0
    package var maxPassesPerUpdate = 16

    package let timeSource: any AnimationTimeSource
    package private(set) var currentTime: TimeInterval = 0
    package private(set) var passTransaction = Transaction()
    package private(set) var lowerGeneration = 0
    package private(set) var frameCount = 0
    private var drivers: [any AnimationDriver] = []
    private var driverIDs: Set<ObjectIdentifier> = []
    private var completionQueue: [() -> Void] = []
    private var passRecords: [AnimationCompletionRecord] = []
    private var passRecordIDs: Set<ObjectIdentifier> = []
    package private(set) var ghosts: [Ghost] = []
    private var matched: [MatchedGeometryState] = []

    private var appearQueue: [() -> Void] = []
    private var disappearQueue: [() -> Void] = []
    private var geometryActions: [() -> Void] = []
    private var preferenceActions: [() -> Void] = []

    package var onBodyEvaluation: ((ViewNode) -> Void)?

    package init<V: View>(rootView: V, environment: EnvironmentValues = EnvironmentValues(), layout: HostLayout? = nil,
                          timeSource: (any AnimationTimeSource)? = nil) {
        self.rootView = rootView
        self.environment = environment
        self.layout = layout
        self.timeSource = timeSource ?? ManualAnimationClock()
    }

    package var clock: ManualAnimationClock? { timeSource as? ManualAnimationClock }

    package func setRootView<V: View>(_ view: V) {
        rootView = view
        rootViewChanged = true
        needsUpdate = true
    }

    package func updateEnvironment(_ body: (inout EnvironmentValues) -> Void) {
        body(&environment)
    }

    package func update() {
        var passes = 0
        while needsUpdate && passes < maxPassesPerUpdate {
            runPass()
            passes += 1
        }
    }

    package func step() {
        if needsUpdate { runPass() }
    }

    package func scheduleUpdate(transaction: Transaction) {
        needsUpdate = true
        if pendingTransaction == nil || !transaction.isEmpty {
            var t = transaction
            if let completions = pendingTransaction?.completions, !completions.isEmpty {
                t.completions = completions + t.completions
            }
            pendingTransaction = t
        }
    }

    package func noteBodyEvaluation(_ node: ViewNode) { onBodyEvaluation?(node) }

    package func activate(_ driver: any AnimationDriver) {
        if driverIDs.insert(ObjectIdentifier(driver)).inserted { drivers.append(driver) }
    }

    package var isAnimating: Bool { drivers.contains { $0.isActive } || !ghosts.isEmpty }

    package func hasActiveDrivers(in node: ViewNode) -> Bool {
        drivers.contains { d in d.isActive && (d.owner.map { $0.isDescendant(of: node) } ?? false) }
    }

    package func driversStarted(in node: ViewNode) -> [any AnimationDriver] {
        drivers.filter { d in
            d.isActive && d.runStart.map { abs($0 - currentTime) < 1e-9 } == true
                && (d.owner.map { $0.isDescendant(of: node) } ?? false)
        }
    }

    package func noteCompletions(_ records: [AnimationCompletionRecord]) {
        for r in records where passRecordIDs.insert(ObjectIdentifier(r)).inserted { passRecords.append(r) }
    }

    package func queueCompletion(_ action: @escaping () -> Void) { completionQueue.append(action) }

    private func runCompletions() {
        while !completionQueue.isEmpty {
            let q = completionQueue
            completionQueue = []
            for c in q { c() }
        }
    }

    package func renderFrame() {
        frameCount += 1
        update()
        currentTime = timeSource.now
        var changed: [() -> Void] = []
        var kept: [any AnimationDriver] = []
        for d in drivers {
            if let o = d.owner, !o.isAlive {
                d.cancel()
            } else if d.sample(at: currentTime), let f = d.onChange {
                changed.append(f)
            }
            if d.isActive { kept.append(d) } else { driverIDs.remove(ObjectIdentifier(d)) }
        }
        drivers = kept
        let ended = ghosts.filter { g in !(g.parent?.isAlive ?? false) || !g.waitFor.contains { $0.isActive } }
        if !changed.isEmpty || !ended.isEmpty {
            passCount += 1
            passTransaction = Transaction()
            for f in changed { f() }
            ghosts.removeAll { g in ended.contains { $0.node === g.node } }
            for g in ended { g.node.teardown() }
            finishPass(animatedGeometry: false)
        } else {
            runCompletions()
        }
        update()
    }

    package func advance(frames: Int = 1) {
        guard let clock else { return }
        for _ in 0..<frames {
            clock.advance()
            renderFrame()
        }
    }

    package func advance(seconds: TimeInterval) {
        guard let clock else { return }
        advance(frames: Int((seconds * clock.framesPerSecond).rounded()))
    }

    package func settle(maxFrames: Int = 3600) {
        var n = 0
        while isAnimating && n < maxFrames {
            advance()
            n += 1
        }
    }

    package struct Ghost {
        package let node: ViewNode
        package weak var parent: ViewNode?
        package let placements: [(parent: AffineTransform2D, origin: CGPoint, size: CGSize, proposal: ProposedViewSize)]
        package let waitFor: [any AnimationDriver]
    }

    package func registerMatched(_ state: MatchedGeometryState) { matched.append(state) }

    package func matchedStates() -> [MatchedGeometryState] {
        matched.removeAll { !($0.node?.isAlive ?? false) }
        return matched
    }

    package func addGhost(_ node: ViewNode, waitingFor: [any AnimationDriver]) {
        var placements: [(AffineTransform2D, CGPoint, CGSize, ProposedViewSize)] = []
        for n in node.lastLowered {
            guard let t = n.placedTransform, let o = n.placedLocalOrigin, let s = n.placedSize,
                  let p = n.placedProposal else { continue }
            placements.append((t.concatenating(.translation(-o.x, -o.y)), o, s, p))
        }
        ghosts.append(Ghost(node: node, parent: node.parent, placements: placements, waitFor: waitingFor))
    }

    package func queueAppear(_ action: @escaping () -> Void) { appearQueue.append(action) }
    package func queueDisappear(_ action: @escaping () -> Void) { disappearQueue.append(action) }
    package func queueGeometryAction(_ action: @escaping () -> Void) { geometryActions.append(action) }
    package func queuePreferenceAction(_ action: @escaping () -> Void) { preferenceActions.append(action) }

    private func runPass() {
        needsUpdate = false
        passCount += 1
        currentTime = timeSource.now
        let transaction = pendingTransaction ?? Transaction()
        pendingTransaction = nil
        passTransaction = transaction
        noteCompletions(transaction.completions)

        let changed = rootViewChanged
        rootViewChanged = false
        if let root {
            root.update(changed ? rootView : nil, environment: environment, transaction: transaction)
        } else {
            let r = ViewNode(graph: self, parent: nil, view: rootView)
            root = r
            r.update(rootView, environment: environment, transaction: transaction)
        }
        for g in ghosts where g.node.isAlive {
            g.node.update(nil, environment: g.node.environment, transaction: transaction)
        }
        finishPass(animatedGeometry: true)
    }

    private func finishPass(animatedGeometry: Bool) {
        let appear = appearQueue
        appearQueue = []
        for a in appear.reversed() { a() }
        let disappear = disappearQueue
        disappearQueue = []
        for d in disappear.reversed() { d() }

        if let layout { performLayout(layout, animated: animatedGeometry) }

        let geo = geometryActions
        geometryActions = []
        for g in geo { g() }
        rootPreferences = root?.preferenceValues() ?? PreferenceValues()
        let prefs = preferenceActions
        preferenceActions = []
        for p in prefs { p() }

        let records = passRecords
        passRecords = []
        passRecordIDs = []
        for r in records { r.seal(graph: self) }
        runCompletions()
    }

    package func beginLowering() { lowerGeneration += 1 }

    package func rootLayoutNode() -> LayoutNode {
        beginLowering()
        let nodes = root?.lower() ?? []
        if nodes.count == 1 { return nodes[0] }
        if nodes.isEmpty { return .empty() }
        return .vstack(nodes)
    }

    private func performLayout(_ layout: HostLayout, animated: Bool) {
        let node = rootLayoutNode()
        let engine = LayoutEngine(environment: environment, textMeasurer: layout.textMeasurer, symbols: layout.symbols)
        let result: LayoutResult
        switch layout.mode {
        case .window(let size, let insets): result = engine.layout(node, window: size, safeAreaInsets: insets)
        case .proposal(let p): result = engine.layout(node, proposal: p)
        }
        layoutResult = result
        node.forEachNode { n in
            guard let owner = n.owner as? ViewNode, owner.isAlive, let frame = result.frame(of: n) else { return }
            let g = NodeGeometry(size: n.placedSize ?? frame.size, frame: frame, safeAreaInsets: result.safeAreaInsets(of: n))
            if let observer = owner.primitiveState as? GeometryObserving {
                observer.geometryChanged(g, node: owner)
            }
            owner.geometry = g
        }
        node.forEachNode { n in
            guard let creator = n.creator as? ViewNode, creator.isAlive, let o = n.placedLocalOrigin,
                  let s = n.placedSize else { return }
            let r = CGRect(origin: o, size: s)
            guard r.minX.isFinite, r.minY.isFinite, r.width.isFinite, r.height.isFinite else { return }
            creator.recordFrame(index: n.creatorIndex, r,
                                transaction: animated ? creator.transactionForSelf() : Transaction())
        }
        if !matched.isEmpty { updateMatchedGeometry(animated: animated) }
    }

    package func frame(named name: String) -> CGRect? { layoutResult?.namedFrames[name] }

    package static func layoutNode<V: View>(for view: V, environment: EnvironmentValues = EnvironmentValues()) -> LayoutNode {
        let g = ViewGraph(rootView: view, environment: environment)
        g.update()
        return g.rootLayoutNode()
    }
}

@MainActor
package protocol GeometryObserving: AnyObject {
    func geometryChanged(_ geometry: NodeGeometry, node: ViewNode)
}
