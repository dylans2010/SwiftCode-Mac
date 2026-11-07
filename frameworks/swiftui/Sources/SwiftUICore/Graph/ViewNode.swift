import Foundation
import Observation

package final class WeakNode: @unchecked Sendable {
    package weak var node: ViewNode?
    package init(_ node: ViewNode) { self.node = node }

    package nonisolated func invalidate() {
        if MainActorCheck.isCurrent {
            let tx = Transaction._current
            MainActor.assumeIsolated { node?.invalidate(transaction: tx) }
        } else {
            Task { @MainActor in self.node?.invalidate(transaction: Transaction()) }
        }
    }
}

package class DependencySource: @unchecked Sendable {
    private var dependents: [ObjectIdentifier: WeakNode] = [:]

    package init() {}

    @MainActor package func addDependent(_ node: ViewNode) {
        dependents[ObjectIdentifier(node)] = WeakNode(node)
    }

    @MainActor package func removeDependent(_ node: ViewNode) {
        dependents[ObjectIdentifier(node)] = nil
    }

    @MainActor package func invalidateDependents(transaction: Transaction) {
        for (id, ref) in dependents {
            guard let n = ref.node, n.isAlive else { dependents[id] = nil; continue }
            n.invalidate(transaction: transaction)
        }
    }
}

package enum DependencyTracker {
    nonisolated(unsafe) package static var current: ViewNode?

    package static func recordRead(_ source: DependencySource) {
        guard MainActorCheck.isCurrent, current != nil else { return }
        MainActor.assumeIsolated { current?.addDependency(source) }
    }

    @MainActor
    package static func recordEnvironmentRead(node: ViewNode?, key: AnyHashable, value: Any,
                                              read: @escaping (EnvironmentValues) -> Any) {
        guard let cur = current, let node, cur === node else { return }
        node.addEnvironmentDependency(key: key, value: value, read: read)
    }
}

@MainActor
package final class ViewNode {
    package enum Kind { case custom, primitive }

    package unowned let graph: ViewGraph
    package private(set) weak var parent: ViewNode?
    package private(set) var view: any View
    package let kind: Kind
    package private(set) var environment = EnvironmentValues()
    package var childEnvironment: EnvironmentValues { environmentOverride ?? environment }
    package var environmentOverride: EnvironmentValues?
    package var primitiveEnvironmentCache: UInt64?
    package private(set) var children: [ViewNode] = []
    package private(set) var childKeys: [AnyHashable] = []

    package private(set) var isAlive = true
    private var isNew = true
    package var isDirty = false
    package var hasDirtyDescendant = false

    package private(set) var updateEnvironmentChanged = false
    package private(set) var updateWasDirty = false
    package private(set) var updateHadDirtyDescendant = false

    package private(set) var bodyCount = 0

    package var slots: [Int: AnyObject] = [:]
    private var sources: [ObjectIdentifier: DependencySource] = [:]
    private var environmentDependencies: [AnyHashable: (value: Any, read: (EnvironmentValues) -> Any)] = [:]

    package var primitiveState: AnyObject?
    package var modifierContent: (any View)?
    private var placeholders: [WeakNode] = []

    package var geometry: NodeGeometry?

    package let createdPass: Int
    private var childTx = Transaction()
    private var childTxStamp = -1
    package weak var insertionRoot: ViewNode?
    package var insertionTransaction: Transaction?
    package var transitionClaimed = false
    package var transitionOpacity: Animator<Double>?
    package var bodyAnimator: AnyObject?
    package var frameAnimators: [Int: Animator<CGRect.AnimatableData>] = [:]
    package private(set) var lastLowered: [LayoutNode] = []
    private var lowerGeneration = -1
    private var lowerCounter = 0

    package init(graph: ViewGraph, parent: ViewNode?, view: any View) {
        self.graph = graph
        self.parent = parent
        self.view = view
        self.kind = view is any PrimitiveView ? .primitive : .custom
        self.createdPass = graph.passCount
    }

    package func update(_ newView: (any View)?, environment env: EnvironmentValues, transaction: Transaction) {
        guard isAlive else { return }
        let first = isNew
        isNew = false
        setChildTransaction(transaction)
        let envChanged = first || env.revision != environment.revision
        environment = env
        let old: (any View)? = first ? nil : view
        if let v = newView { view = v }
        let dirty = isDirty, dirtyDescendant = hasDirtyDescendant
        isDirty = false
        hasDirtyDescendant = false
        updateEnvironmentChanged = envChanged
        updateWasDirty = dirty
        updateHadDirtyDescendant = dirtyDescendant
        switch kind {
        case .custom:
            let inputsChanged = old == nil || (newView != nil && !GraphComparison.fieldsEqual(old!, view))
            let presented = presentedCustomView(isNewValue: newView != nil, transaction: transaction)
            updateTracked(inputs: presented ?? view, inputsChanged: inputsChanged, transaction: transaction) {
                evaluateBody(of: presented ?? self.view)
            }
        case .primitive:
            let p = view as! any PrimitiveView
            if newView != nil || first {
                makeChildren(p, old: old, transaction: transaction)
            } else if envChanged || dirty || dirtyDescendant {
                p._refresh(node: self, environmentChanged: envChanged, transaction: transaction)
            }
        }
    }

    private func makeChildren<P: PrimitiveView>(_ p: P, old: (any View)?, transaction: Transaction) {
        p._makeChildren(node: self, old: old as? P, transaction: transaction)
    }

    @discardableResult
    package func updateTracked(inputs: Any, inputsChanged: Bool, transaction: Transaction,
                               evaluate: () -> any View) -> Bool {
        let envDependencyChanged = updateEnvironmentChanged && environmentDependenciesChanged()
        if inputsChanged || updateWasDirty || envDependencyChanged {
            let body = runTracked(inputs: inputs, evaluate)
            reconcileChildren([(AnyHashable(0), body)], transaction: transaction)
            return true
        }
        if updateEnvironmentChanged || updateHadDirtyDescendant {
            refreshChildren(transaction: transaction)
        }
        return false
    }

    package func runTracked(inputs: Any, _ evaluate: () -> any View) -> any View {
        clearDependencies()
        DynamicPropertyInstaller.install(inputs, in: self)
        let previous = DependencyTracker.current
        DependencyTracker.current = self
        defer { DependencyTracker.current = previous }
        let ref = WeakNode(self)
        let body = withObservationTracking {
            evaluate()
        } onChange: {
            ref.invalidate()
        }
        bodyCount += 1
        graph.noteBodyEvaluation(self)
        return body
    }

    package func trackContent<T>(_ evaluate: () -> T) -> T {
        clearDependencies()
        let previous = DependencyTracker.current
        DependencyTracker.current = self
        defer { DependencyTracker.current = previous }
        let ref = WeakNode(self)
        return withObservationTracking {
            evaluate()
        } onChange: {
            ref.invalidate()
        }
    }

    package func refreshChildren(transaction: Transaction) {
        let env = childEnvironment
        for c in children { c.update(nil, environment: env, transaction: transaction) }
    }

    package func reconcileChildren(_ items: [(AnyHashable, any View)], transaction: Transaction) {
        var oldByKey: [AnyHashable: ViewNode] = [:]
        var oldOrder: [AnyHashable] = []
        for (k, c) in zip(childKeys, children) where oldByKey[k] == nil {
            oldByKey[k] = c
            oldOrder.append(k)
        }
        var newChildren: [ViewNode] = []
        var newKeys: [AnyHashable] = []
        newChildren.reserveCapacity(items.count)
        let env = childEnvironment
        var toUpdate: [(ViewNode, any View)] = []
        var inserted: [ViewNode] = []
        for (key, v) in items {
            if let c = oldByKey[key], ObjectIdentifier(type(of: c.view)) == ObjectIdentifier(type(of: v)) {
                oldByKey[key] = nil
                newChildren.append(c)
                toUpdate.append((c, v))
            } else {
                let c = ViewNode(graph: graph, parent: self, view: v)
                if createdPass == graph.passCount {
                    if passesInsertion(toChildKey: key) { c.insertionRoot = insertionRoot }
                } else {
                    c.insertionRoot = c
                    c.insertionTransaction = transaction
                    inserted.append(c)
                }
                newChildren.append(c)
                toUpdate.append((c, v))
            }
            newKeys.append(key)
        }
        for k in oldOrder { if let c = oldByKey[k] { remove(c, transaction: transaction) } }
        children = newChildren
        childKeys = newKeys
        for (c, v) in toUpdate { c.update(v, environment: env, transaction: transaction) }
        for c in inserted where !c.transitionClaimed && transaction.animation != nil {
            let fade = Animator<Double>(0, owner: c)
            c.transitionOpacity = fade
            fade.update(to: 1, transaction: transaction, graph: graph)
        }
    }

    private func remove(_ c: ViewNode, transaction: Transaction) {
        if let t = c.transitionNode(), let state = t.primitiveState as? TransitionState,
           let animation = state.animation ?? transaction.animation {
            var tx = transaction
            tx.animation = animation
            t.applyTransitionPhase(.didDisappear, transaction: tx)
        } else if transaction.animation != nil {
            let fade = c.transitionOpacity ?? Animator<Double>(1, owner: c)
            c.transitionOpacity = fade
            fade.update(to: 0, transaction: transaction, graph: graph)
        }
        let removal = graph.driversStarted(in: c)
        if !removal.isEmpty {
            graph.addGhost(c, waitingFor: removal)
        } else {
            c.teardown()
        }
    }

    package func transitionNode() -> ViewNode? {
        var n = self
        while true {
            if n.primitiveState is TransitionState, n.view is any TransitionHosting { return n }
            guard let first = n.children.first, n.passesInsertion(toChildKey: n.childKeys[0]) else { return nil }
            n = first
        }
    }

    package func passesInsertion(toChildKey key: AnyHashable) -> Bool {
        switch kind {
        case .custom: return true
        case .primitive: return (view as? any InsertionChaining)?._passesInsertion(childKey: key) ?? false
        }
    }

    package func isDescendant(of ancestor: ViewNode) -> Bool {
        var n: ViewNode? = self
        while let m = n {
            if m === ancestor { return true }
            n = m.parent
        }
        return false
    }

    package func setChildTransaction(_ t: Transaction) {
        childTx = t
        childTxStamp = graph.passCount
    }

    package func transactionForChildren() -> Transaction {
        if childTxStamp == graph.passCount { return childTx }
        let incoming = transactionForSelf()
        let t = (view as? any TransactionRewriting)?._unchangedTransaction(incoming, node: self) ?? incoming
        setChildTransaction(t)
        return t
    }

    package func transactionForSelf() -> Transaction {
        parent?.transactionForChildren() ?? graph.passTransaction
    }

    private func presentedCustomView(isNewValue: Bool, transaction: Transaction) -> (any View)? {
        guard let a = view as? any Animatable else { return nil }
        return presentedAnimatable(a, isNewValue: isNewValue, transaction: transaction) { [weak self] in
            self?.customViewFrame()
        } as? any View
    }

    private func customViewFrame() {
        guard isAlive else { return }
        let tx = Transaction()
        setChildTransaction(tx)
        let presented = presentedCustomView(isNewValue: false, transaction: tx)
        updateTracked(inputs: presented ?? view, inputsChanged: true, transaction: tx) {
            evaluateBody(of: presented ?? self.view)
        }
    }

    package func presentedAnimatable<A: Animatable>(_ a: A, isNewValue: Bool, transaction: Transaction,
                                                    onFrame: @escaping () -> Void) -> A? {
        if A.AnimatableData.self == EmptyAnimatableData.self { return nil }
        let data = a.animatableData
        let animator: Animator<A.AnimatableData>
        if let existing = bodyAnimator as? Animator<A.AnimatableData> {
            animator = existing
            if isNewValue { animator.update(to: data, transaction: transaction, graph: graph) }
        } else {
            animator = Animator(data, owner: self)
            bodyAnimator = animator
        }
        animator.onChange = onFrame
        var copy = a
        copy.animatableData = animator.presented
        return copy
    }

    package func recordFrame(index: Int, _ frame: CGRect, transaction: Transaction) {
        let data = frame.animatableData
        if let a = frameAnimators[index] {
            a.update(to: data, transaction: transaction, graph: graph)
        } else {
            frameAnimators[index] = Animator(data, owner: self)
        }
    }

    package func presentedFrame(index: Int) -> CGRect? {
        guard let a = frameAnimators[index], a.isActive else { return nil }
        var r = CGRect.zero
        r.animatableData = a.presented
        return r
    }

    package func teardown() {
        guard isAlive else { return }
        if kind == .primitive, let p = view as? any PrimitiveView { p._removed(node: self) }
        for c in children { c.teardown() }
        isAlive = false
        clearDependencies()
        slots.removeAll()
        children = []
        childKeys = []
        parent = nil
    }

    package private(set) var isSuspended = false

    package func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended, isAlive else { return }
        isSuspended = suspended
        func walk(_ n: ViewNode) {
            if n !== self && n.isSuspended { return }
            (n.primitiveState as? any VisibilityObserving)?.visibilityChanged(!suspended, node: n)
            for c in n.children { walk(c) }
        }
        walk(self)
    }

    package var isInSuspendedSubtree: Bool {
        var n: ViewNode? = self
        while let m = n {
            if m.isSuspended { return true }
            n = m.parent
        }
        return false
    }

    package func invalidate(transaction: Transaction) {
        guard isAlive else { return }
        isDirty = true
        var p = parent
        while let q = p, !q.hasDirtyDescendant {
            q.hasDirtyDescendant = true
            p = q.parent
        }
        graph.scheduleUpdate(transaction: transaction)
    }

    package func addDependency(_ source: DependencySource) {
        sources[ObjectIdentifier(source)] = source
        source.addDependent(self)
    }

    package func addEnvironmentDependency(key: AnyHashable, value: Any, read: @escaping (EnvironmentValues) -> Any) {
        if environmentDependencies[key] == nil { environmentDependencies[key] = (value, read) }
    }

    private func clearDependencies() {
        for s in sources.values { s.removeDependent(self) }
        sources = [:]
        environmentDependencies = [:]
    }

    private func environmentDependenciesChanged() -> Bool {
        for (_, dep) in environmentDependencies where !GraphComparison.valuesEqual(dep.read(environment), dep.value) {
            return true
        }
        return false
    }

    package func registerPlaceholder(_ node: ViewNode) {
        placeholders.removeAll { $0.node == nil || $0.node === node }
        placeholders.append(WeakNode(node))
    }

    package func pushContentToPlaceholders(transaction: Transaction) {
        guard let content = modifierContent else { return }
        for ref in placeholders {
            guard let ph = ref.node, ph.isAlive else { continue }
            ph.reconcileChildren([(AnyHashable(0), content)], transaction: transaction)
        }
    }

    package func lower() -> [LayoutNode] {
        switch kind {
        case .custom: return finishLowering(lowerChildren())
        case .primitive: return finishLowering((view as! any PrimitiveView)._lower(node: self))
        }
    }

    private func finishLowering(_ nodes: [LayoutNode]) -> [LayoutNode] {
        if lowerGeneration != graph.lowerGeneration {
            lowerGeneration = graph.lowerGeneration
            lowerCounter = 0
        }
        var out = nodes
        if let fade = transitionOpacity, fade.isActive || fade.model != 1 {
            out = out.map { n in
                let w = LayoutNode(OpacityBehavior(fade.model), children: [n])
                w.presentation = .opacity { fade.presented }
                return w
            }
        }
        for n in out {
            n.forEachNode { m in
                if m.creator == nil {
                    m.creator = self
                    m.creatorIndex = lowerCounter
                    lowerCounter += 1
                }
            }
        }
        lastLowered = out
        return out
    }

    package func lowerChildren() -> [LayoutNode] { children.flatMap { $0.lower() } }

    package func preferenceValues() -> PreferenceValues {
        switch kind {
        case .custom: return childPreferences()
        case .primitive: return (view as! any PrimitiveView)._preferences(node: self)
        }
    }

    package func childPreferences() -> PreferenceValues {
        var r = PreferenceValues()
        for c in children { r.combine(with: c.preferenceValues()) }
        return r
    }

    package func forEachNode(_ body: (ViewNode) -> Void) {
        body(self)
        for c in children { c.forEachNode(body) }
    }
}

@MainActor
package protocol VisibilityObserving: AnyObject {
    func visibilityChanged(_ visible: Bool, node: ViewNode)
}

package struct NodeGeometry: Equatable {
    package var size: CGSize
    package var frame: CGRect
    package var safeAreaInsets: EdgeInsets

    package init(size: CGSize = .zero, frame: CGRect = .zero, safeAreaInsets: EdgeInsets = EdgeInsets()) {
        self.size = size
        self.frame = frame
        self.safeAreaInsets = safeAreaInsets
    }
}

@MainActor
package func evaluateBody(of view: any View) -> any View {
    func open<V: View>(_ v: V) -> any View { v.body }
    return open(view)
}
