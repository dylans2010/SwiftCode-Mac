import Foundation

private final class AppearanceState: VisibilityObserving {
    var appear: (() -> Void)?
    var disappear: (() -> Void)?
    var visible = true
    init(_ a: (() -> Void)?, _ d: (() -> Void)?) {
        appear = a
        disappear = d
    }

    func visibilityChanged(_ v: Bool, node: ViewNode) {
        guard v != visible else { return }
        visible = v
        if v, let appear { node.graph.queueAppear(appear) }
        if !v, let disappear { node.graph.queueDisappear(disappear) }
    }
}

package struct AppearanceActionModifier: PrimitiveModifier {
    package var appear: (() -> Void)?
    package var disappear: (() -> Void)?

    package func _inserted(node: ViewNode) {
        node.primitiveState = AppearanceState(appear, disappear)
        if let appear { node.graph.queueAppear(appear) }
    }

    package func _updated(old: AppearanceActionModifier, node: ViewNode) {
        guard let s = node.primitiveState as? AppearanceState else { return }
        s.appear = appear
        s.disappear = disappear
    }

    package func _removed(node: ViewNode) {
        if let s = node.primitiveState as? AppearanceState, s.visible, let d = s.disappear { node.graph.queueDisappear(d) }
    }
}

private final class ValueActionState<V> {
    var value: V
    init(_ v: V) { value = v }
}

package struct ValueActionModifier<V: Equatable>: PrimitiveModifier {
    package let value: V
    package let initial: Bool
    package let action: (V, V) -> Void

    package func _inserted(node: ViewNode) {
        node.primitiveState = ValueActionState(value)
        if initial {
            let v = value, action = action
            node.graph.queueAppear { action(v, v) }
        }
    }

    package func _updated(old: ValueActionModifier, node: ViewNode) {
        guard let state = node.primitiveState as? ValueActionState<V> else { return }
        let previous = state.value
        state.value = value
        if previous != value { action(previous, value) }
    }
}

private final class TaskState: VisibilityObserving {
    var task: Task<Void, Never>?
    var restart: (() -> Void)?
    func cancel() {
        task?.cancel()
        task = nil
    }

    func visibilityChanged(_ v: Bool, node: ViewNode) {
        if v {
            if let restart { node.graph.queueAppear(restart) }
        } else {
            node.graph.queueDisappear { [weak self] in self?.cancel() }
        }
    }
}

package struct TaskModifier: PrimitiveModifier {
    package let id: AnyHashable?
    package let priority: TaskPriority
    package let action: @MainActor () async -> Void

    private func start(_ state: TaskState) {
        let action = self.action
        state.task = Task(priority: priority) { @MainActor in await action() }
    }

    package func _inserted(node: ViewNode) {
        let state = TaskState()
        node.primitiveState = state
        state.restart = { [weak state] in if let state { self.start(state) } }
        node.graph.queueAppear { self.start(state) }
    }

    package func _updated(old: TaskModifier, node: ViewNode) {
        guard let state = node.primitiveState as? TaskState else { return }
        state.restart = { [weak state] in if let state { self.start(state) } }
        guard old.id != id else { return }
        node.graph.queueAppear {
            state.cancel()
            self.start(state)
        }
    }

    package func _removed(node: ViewNode) {
        guard let state = node.primitiveState as? TaskState else { return }
        node.graph.queueDisappear { state.cancel() }
    }
}

extension TaskModifier: GraphInputComparable {
    package nonisolated func _isGraphInputEqual(to other: Any) -> Bool { false }
}

package struct TransactionModifier: PrimitiveModifier {
    package let transform: (inout Transaction) -> Void

    package func _transaction(_ transaction: Transaction, old: TransactionModifier?, node: ViewNode) -> Transaction {
        var t = transaction
        transform(&t)
        return t
    }
}

package struct ValueTransactionModifier<V: Equatable>: PrimitiveModifier {
    package let value: V
    package let transform: (inout Transaction) -> Void

    package func _transaction(_ transaction: Transaction, old: ValueTransactionModifier?, node: ViewNode) -> Transaction {
        guard let old, old.value != value else { return transaction }
        var t = transaction
        transform(&t)
        return t
    }
}

package struct AnimationModifier<V: Equatable>: PrimitiveModifier {
    package let animation: Animation?
    package let value: V

    package func _transaction(_ transaction: Transaction, old: AnimationModifier?, node: ViewNode) -> Transaction {
        guard let old, old.value != value, !transaction.disablesAnimations else { return transaction }
        var t = transaction
        t.animation = animation
        return t
    }
}

package struct RenderEffectModifier<Value: Equatable>: PrimitiveModifier {
    package let name: String
    package let value: Value
}

extension View {
    public func onAppear(perform action: (() -> Void)? = nil) -> some View {
        modifier(AppearanceActionModifier(appear: action, disappear: nil))
    }

    public func onDisappear(perform action: (() -> Void)? = nil) -> some View {
        modifier(AppearanceActionModifier(appear: nil, disappear: action))
    }

    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        modifier(ValueActionModifier(value: value, initial: initial, action: action))
    }

    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping () -> Void) -> some View {
        modifier(ValueActionModifier(value: value, initial: initial) { _, _ in action() })
    }

    @available(*, deprecated, message: "Use onChange with a two or zero parameter action closure instead.")
    public func onChange<V: Equatable>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View {
        modifier(ValueActionModifier(value: value, initial: false) { _, new in action(new) })
    }

    public func task(priority: TaskPriority = .userInitiated,
                     _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(TaskModifier(id: nil, priority: priority, action: action))
    }

    public func task<T: Equatable & Hashable>(id value: T, priority: TaskPriority = .userInitiated,
                                              _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(TaskModifier(id: AnyHashable(value), priority: priority, action: action))
    }

    public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(TransactionModifier(transform: transform))
    }

    public func transaction<V: Equatable>(value: V, _ transform: @escaping (inout Transaction) -> Void) -> some View {
        modifier(ValueTransactionModifier(value: value, transform: transform))
    }

    public func animation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AnimationModifier(animation: animation, value: value))
    }

    public func hidden() -> some View { modifier(NodeRenderEffectModifier(name: "hidden") { .hidden }) }
}
