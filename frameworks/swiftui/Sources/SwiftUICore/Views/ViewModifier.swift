import Foundation

@MainActor @preconcurrency
public protocol ViewModifier {
    associatedtype Body: View
    @ViewBuilder @MainActor @preconcurrency func body(content: Content) -> Body
    typealias Content = _ViewModifier_Content<Self>
}

extension ViewModifier where Body == Never {
    public func body(content: Content) -> Never { fatalError("\(Self.self) is a primitive modifier") }
}

extension ViewModifier {
    public func concat<T>(_ modifier: T) -> ModifiedContent<Self, T> { ModifiedContent(content: self, modifier: modifier) }
}

public struct ModifiedContent<Content, Modifier> {
    public var content: Content
    public var modifier: Modifier

    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {}

extension ModifiedContent: View where Content: View, Modifier: ViewModifier {
    public typealias Body = Never
}

extension ModifiedContent: ViewModifier where Content: ViewModifier, Modifier: ViewModifier {
    public func body(content: _ViewModifier_Content<ModifiedContent<Content, Modifier>>) -> some View {
        content.modifier(self.content).modifier(self.modifier)
    }
}

extension View {
    public func modifier<T>(_ modifier: T) -> ModifiedContent<Self, T> { ModifiedContent(content: self, modifier: modifier) }
}

public struct EmptyModifier: ViewModifier, Sendable {
    public static let identity = EmptyModifier()
    public init() {}
    public typealias Body = Never
}

extension EmptyModifier: PrimitiveModifier {}

public struct _ViewModifier_Content<Modifier: ViewModifier>: View {
    nonisolated(unsafe) package weak var source: ViewNode?
    package init(source: ViewNode?) { self.source = source }
    public typealias Body = Never
}

extension _ViewModifier_Content: GraphInputComparable {
    package nonisolated func _isGraphInputEqual(to other: Any) -> Bool {
        guard let o = other as? _ViewModifier_Content<Modifier> else { return false }
        return o.source === source
    }
}

extension _ViewModifier_Content: PrimitiveView {
    package func _makeChildren(node: ViewNode, old: _ViewModifier_Content?, transaction: Transaction) {
        guard let source, let content = source.modifierContent else {
            node.reconcileChildren([], transaction: transaction)
            return
        }
        source.registerPlaceholder(node)
        node.reconcileChildren([(AnyHashable(0), content)], transaction: transaction)
    }
}

@MainActor
package protocol PrimitiveModifier: ViewModifier where Body == Never {
    var _writesEnvironment: Bool { get }
    func _environment(_ env: EnvironmentValues) -> EnvironmentValues
    func _transaction(_ transaction: Transaction, old: Self?, node: ViewNode) -> Transaction
    func _inserted(node: ViewNode)
    func _updated(old: Self, node: ViewNode)
    func _removed(node: ViewNode)
    func _animate(old: Self?, node: ViewNode, transaction: Transaction)
    func _secondary(node: ViewNode) -> (any View)?
    var _rebuildsWhenDirty: Bool { get }
    func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode]
    func _preferences(_ content: PreferenceValues, secondary: PreferenceValues?, node: ViewNode) -> PreferenceValues
}

extension PrimitiveModifier {
    package var _writesEnvironment: Bool { false }
    package func _environment(_ env: EnvironmentValues) -> EnvironmentValues { env }
    package func _transaction(_ transaction: Transaction, old: Self?, node: ViewNode) -> Transaction { transaction }
    package func _inserted(node: ViewNode) {}
    package func _updated(old: Self, node: ViewNode) {}
    package func _removed(node: ViewNode) {}
    package func _animate(old: Self?, node: ViewNode, transaction: Transaction) {}
    package func _secondary(node: ViewNode) -> (any View)? { nil }
    package var _rebuildsWhenDirty: Bool { false }
    package func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode] { content }
    package func _preferences(_ content: PreferenceValues, secondary: PreferenceValues?, node: ViewNode) -> PreferenceValues {
        var p = content
        if let secondary { p.combine(with: secondary) }
        return p
    }
}

@MainActor
extension ModifiedContent: PrimitiveView where Content: View, Modifier: ViewModifier {
    package func _makeChildren(node: ViewNode, old: ModifiedContent?, transaction: Transaction) {
        if let host = self as? any TransitionHosting {
            host._transitionUpdate(node: node, isNew: old == nil, transaction: transaction)
        } else if let pm = modifier as? any PrimitiveModifier {
            primitiveUpdate(pm, node: node, oldModifier: old?.modifier, transaction: transaction)
        } else {
            customUpdate(node: node, oldModifier: old?.modifier, transaction: transaction)
        }
    }

    package func _refresh(node: ViewNode, environmentChanged: Bool, transaction: Transaction) {
        if let pm = modifier as? any PrimitiveModifier {
            primitiveRefresh(pm, node: node, transaction: transaction)
        } else if self is any TransitionHosting {
            node.refreshChildren(transaction: transaction)
        } else {
            node.modifierContent = content
            let presented = presentedModifier(node: node, isNewValue: false, transaction: transaction)
            node.updateTracked(inputs: presented ?? modifier, inputsChanged: false, transaction: transaction) {
                evaluateModifierBody(presented ?? self.modifier, node: node)
            }
        }
    }

    package func _removed(node: ViewNode) {
        if let pm = modifier as? any PrimitiveModifier { callRemoved(pm, node: node) }
    }

    package func _lower(node: ViewNode) -> [LayoutNode] {
        guard let pm = modifier as? any PrimitiveModifier else { return node.lowerChildren() }
        let children = node.children
        let content = children.first?.lower() ?? []
        return callLower(pm, content: content, secondary: { children.count > 1 ? children[1].lower() : [] }, node: node)
    }

    package func _preferences(node: ViewNode) -> PreferenceValues {
        guard let pm = modifier as? any PrimitiveModifier else { return node.childPreferences() }
        let children = node.children
        let content = children.first?.preferenceValues() ?? PreferenceValues()
        let secondary = children.count > 1 ? children[1].preferenceValues() : nil
        return callPreferences(pm, content: content, secondary: secondary, node: node)
    }

    private func primitiveUpdate<M: PrimitiveModifier>(_ m: M, node: ViewNode, oldModifier: Modifier?,
                                                       transaction: Transaction) {
        let old = oldModifier as? M
        if let old { m._updated(old: old, node: node) } else { m._inserted(node: node) }
        if m._writesEnvironment {
            let cache = node.primitiveEnvironmentCache
            let unchanged = old.map { GraphComparison.fieldsEqual($0, m) } ?? false
            if !(unchanged && cache == node.environment.revision && node.environmentOverride != nil) {
                node.environmentOverride = m._environment(node.environment)
                node.primitiveEnvironmentCache = node.environment.revision
            }
        }
        m._animate(old: old, node: node, transaction: transaction)
        let tx = m._transaction(transaction, old: old, node: node)
        node.setChildTransaction(tx)
        if !tx.completions.isEmpty { node.graph.noteCompletions(tx.completions) }
        var items: [(AnyHashable, any View)] = [(AnyHashable(0), content)]
        if let s = m._secondary(node: node) { items.append((AnyHashable(1), s)) }
        node.reconcileChildren(items, transaction: tx)
    }

    private func primitiveRefresh<M: PrimitiveModifier>(_ m: M, node: ViewNode, transaction: Transaction) {
        if m._rebuildsWhenDirty && node.updateWasDirty {
            primitiveUpdate(m, node: node, oldModifier: modifier, transaction: transaction)
            return
        }
        if m._writesEnvironment && node.updateEnvironmentChanged {
            node.environmentOverride = m._environment(node.environment)
            node.primitiveEnvironmentCache = node.environment.revision
        }
        let tx = m._transaction(transaction, old: m, node: node)
        node.setChildTransaction(tx)
        node.refreshChildren(transaction: tx)
    }

    private func callRemoved<M: PrimitiveModifier>(_ m: M, node: ViewNode) { m._removed(node: node) }

    private func callLower<M: PrimitiveModifier>(_ m: M, content: [LayoutNode], secondary: () -> [LayoutNode],
                                                 node: ViewNode) -> [LayoutNode] {
        m._lower(content, secondary: secondary, node: node)
    }

    private func callPreferences<M: PrimitiveModifier>(_ m: M, content: PreferenceValues, secondary: PreferenceValues?,
                                                       node: ViewNode) -> PreferenceValues {
        m._preferences(content, secondary: secondary, node: node)
    }

    private func customUpdate(node: ViewNode, oldModifier: Modifier?, transaction: Transaction) {
        node.modifierContent = content
        let inputsChanged = oldModifier.map { !GraphComparison.fieldsEqual($0, modifier) } ?? true
        let presented = presentedModifier(node: node, isNewValue: true, transaction: transaction)
        let ran = node.updateTracked(inputs: presented ?? modifier, inputsChanged: inputsChanged, transaction: transaction) {
            evaluateModifierBody(presented ?? self.modifier, node: node)
        }
        if !ran { node.pushContentToPlaceholders(transaction: transaction) }
    }

    private func presentedModifier(node: ViewNode, isNewValue: Bool, transaction: Transaction) -> Modifier? {
        guard let a = modifier as? any Animatable else { return nil }
        let content = self.content, modifier = self.modifier
        return node.presentedAnimatable(a, isNewValue: isNewValue, transaction: transaction) { [weak node] in
            guard let node, node.isAlive else { return }
            ModifiedContent(content: content, modifier: modifier).animationFrame(node: node)
        } as? Modifier
    }

    private func animationFrame(node: ViewNode) {
        let tx = Transaction()
        node.setChildTransaction(tx)
        node.modifierContent = content
        let presented = presentedModifier(node: node, isNewValue: false, transaction: tx)
        node.updateTracked(inputs: presented ?? modifier, inputsChanged: true, transaction: tx) {
            evaluateModifierBody(presented ?? self.modifier, node: node)
        }
    }
}

@MainActor
private func evaluateModifierBody<M: ViewModifier>(_ m: M, node: ViewNode) -> any View {
    m.body(content: _ViewModifier_Content<M>(source: node))
}
