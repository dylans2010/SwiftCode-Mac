import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty {
    package let box: StateBox<Value>
    package let resetValue: Value

    public init() where Value == Bool {
        box = StateBox(false)
        resetValue = false
    }

    public init<T: Hashable>() where Value == T? {
        box = StateBox(nil)
        resetValue = nil
    }

    public var wrappedValue: Value {
        get { box.location?.read() ?? box.initial }
        nonmutating set { box.location?.write(newValue, transaction: nil) }
    }

    public var projectedValue: Binding {
        Binding(location: box.location, initial: box.initial, resetValue: resetValue)
    }

    @propertyWrapper
    public struct Binding {
        package let location: StateLocation<Value>?
        package let initial: Value
        package let resetValue: Value

        public var wrappedValue: Value {
            get { location?.read() ?? initial }
            nonmutating set { location?.write(newValue, transaction: nil) }
        }

        public var projectedValue: Binding { self }

        package var peek: Value { location?.value ?? initial }
    }
}

extension FocusState: @unchecked Sendable {}

extension FocusState: GraphDynamicProperty {
    package func _install(in node: ViewNode, slot: Int) {
        if let loc = node.slots[slot] as? StateLocation<Value> {
            box.location = loc
        } else {
            let loc = StateLocation(box.initial)
            node.slots[slot] = loc
            box.location = loc
            let graph = node.graph
            loc.onChange = { [weak graph] in graph?.scheduleUpdate(transaction: Transaction()) }
        }
    }
}

extension FocusState: GraphInputComparable {
    package func _isGraphInputEqual(to other: Any) -> Bool { true }
}

@MainActor
package struct FocusBindingRef {
    package let matches: () -> Bool
    package let assign: () -> Void
    package let clear: () -> Void
}

private enum FocusBindingsKey: EnvironmentKey {
    static var defaultValue: [FocusBindingRef] { [] }
}

private enum SubmitActionsKey: EnvironmentKey {
    static var defaultValue: [() -> Void] { [] }
}

extension EnvironmentValues {
    package var _focusBindings: [FocusBindingRef] {
        get { self[FocusBindingsKey.self] }
        set { self[FocusBindingsKey.self] = newValue }
    }

    package var _submitActions: [() -> Void] {
        get { self[SubmitActionsKey.self] }
        set { self[SubmitActionsKey.self] = newValue }
    }
}

public struct SubmitTriggers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let text = SubmitTriggers(rawValue: 1)
    public static let search = SubmitTriggers(rawValue: 2)
}

extension View {
    public func focused(_ binding: FocusState<Bool>.Binding) -> some View {
        let ref = FocusBindingRef(matches: { binding.peek }, assign: { binding.wrappedValue = true },
                                  clear: { if binding.peek { binding.wrappedValue = false } })
        return transformEnvironment(\._focusBindings) { $0.append(ref) }
    }

    public func focused<V: Hashable>(_ binding: FocusState<V>.Binding, equals value: V) -> some View {
        let ref = FocusBindingRef(matches: { binding.peek == value }, assign: { binding.wrappedValue = value },
                                  clear: { if binding.peek == value { binding.wrappedValue = binding.resetValue } })
        return transformEnvironment(\._focusBindings) { $0.append(ref) }
    }

    public func onSubmit(of triggers: SubmitTriggers = .text, _ action: @escaping () -> Void) -> some View {
        transformEnvironment(\._submitActions) { $0.append(action) }
    }

    public func focusable(_ isFocusable: Bool = true) -> some View {
        modifier(FocusableModifier(isFocusable: isFocusable))
    }
}

@MainActor
package protocol TextInputClient: AnyObject {
    func insertText(_ text: String)
    func setMarkedText(_ text: String, cursor: Int)
    func handleKey(_ event: KeyEvent) -> Bool
    var caretRect: CGRect { get }
    func focusChanged(_ focused: Bool)
    func canPerform(_ command: StandardEditCommand, clipboard: (any PlatformClipboard)?) -> Bool
    func perform(_ command: StandardEditCommand, clipboard: (any PlatformClipboard)?)
}

extension TextInputClient {
    package func canPerform(_ command: StandardEditCommand, clipboard: (any PlatformClipboard)?) -> Bool { false }
    package func perform(_ command: StandardEditCommand, clipboard: (any PlatformClipboard)?) {}
}

@MainActor
package final class FocusSystem {
    final class Target {
        weak var node: ViewNode?
        var bindings: [FocusBindingRef]
        weak var client: (any TextInputClient)?
        var keyHandler: ((KeyEvent) -> Bool)?
        var onFocusChange: ((Bool) -> Void)?
        init(node: ViewNode, bindings: [FocusBindingRef], client: (any TextInputClient)?) {
            self.node = node
            self.bindings = bindings
            self.client = client
        }
    }

    private var targets: [ObjectIdentifier: Target] = [:]
    private var order: [ObjectIdentifier] = []
    package private(set) var focusedID: ObjectIdentifier?
    package var onTextClientChanged: ((any TextInputClient)?) -> Void = { _ in }

    package init() {}

    package var focusedClient: (any TextInputClient)? { focusedID.flatMap { targets[$0]?.client } }
    package var focusedKeyHandler: ((KeyEvent) -> Bool)? { focusedID.flatMap { targets[$0]?.keyHandler } }
    package var focusedNode: ViewNode? { focusedID.flatMap { targets[$0]?.node } }

    package func register(_ node: ViewNode, bindings: [FocusBindingRef], client: (any TextInputClient)?,
                          keyHandler: ((KeyEvent) -> Bool)? = nil, onFocusChange: ((Bool) -> Void)? = nil) {
        let id = ObjectIdentifier(node)
        let t: Target
        if let existing = targets[id] {
            t = existing
            t.bindings = bindings
            t.client = client
        } else {
            t = Target(node: node, bindings: bindings, client: client)
            targets[id] = t
            order.append(id)
        }
        t.keyHandler = keyHandler
        t.onFocusChange = onFocusChange
    }

    package func unregister(_ node: ViewNode) { remove(ObjectIdentifier(node)) }

    private func remove(_ id: ObjectIdentifier) {
        guard let t = targets.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        if focusedID == id {
            focusedID = nil
            for b in t.bindings { b.clear() }
            t.client?.focusChanged(false)
            t.onFocusChange?(false)
            onTextClientChanged(nil)
        }
    }

    package func isFocused(_ node: ViewNode) -> Bool { focusedID == ObjectIdentifier(node) }

    package var registeredTargets: [ViewNode] { order.compactMap { targets[$0]?.node } }

    package func focus(_ node: ViewNode?) {
        let newID = node.map(ObjectIdentifier.init)
        guard newID != focusedID, newID == nil || targets[newID!] != nil else { return }
        let old = focusedID.flatMap { targets[$0] }
        let new = newID.flatMap { targets[$0] }
        setFocus(newID)
        for b in old?.bindings ?? [] { b.clear() }
        for b in new?.bindings ?? [] { b.assign() }
    }

    private func setFocus(_ id: ObjectIdentifier?) {
        let old = focusedID.flatMap { targets[$0] }
        focusedID = id
        let new = id.flatMap { targets[$0] }
        old?.client?.focusChanged(false)
        old?.onFocusChange?(false)
        new?.client?.focusChanged(true)
        new?.onFocusChange?(true)
        onTextClientChanged(new?.client)
    }

    private func wanted(_ t: Target) -> Bool { t.bindings.contains { $0.matches() } }

    private var lastWanted: Set<ObjectIdentifier> = []

    package func sync() {
        for id in order where targets[id]?.node?.isAlive != true { remove(id) }
        let nowWanted = Set(order.filter { targets[$0].map(wanted) == true })
        defer { lastWanted = Set(order.filter { targets[$0].map(wanted) == true }) }
        if let id = order.first(where: { nowWanted.contains($0) && !lastWanted.contains($0) && $0 != focusedID }) {
            let old = focusedID.flatMap { targets[$0] }
            setFocus(id)
            for b in old?.bindings ?? [] { b.clear() }
            return
        }
        if let id = focusedID, let t = targets[id], !t.bindings.isEmpty, !wanted(t) {
            setFocus(nil)
        }
        if focusedID.flatMap({ targets[$0] }).map(wanted) != true,
           let id = order.first(where: { $0 != focusedID && targets[$0].map(wanted) == true }) {
            setFocus(id)
        }
    }

    package var modalScopes: [WeakNode] = []

    package func focusNext(in root: ViewNode?, reverse: Bool = false) {
        modalScopes.removeAll { !($0.node?.isAlive ?? false) }
        guard let root = modalScopes.last?.node ?? root else { return }
        var order: [ViewNode] = []
        func walk(_ n: ViewNode) {
            guard !n.isSuspended else { return }
            if targets[ObjectIdentifier(n)] != nil { order.append(n) }
            for c in n.children { walk(c) }
        }
        walk(root)
        guard !order.isEmpty else { return }
        if reverse { order.reverse() }
        let i = order.firstIndex { ObjectIdentifier($0) == focusedID }
        let next = i.map { order[($0 + 1) % order.count] } ?? order[0]
        focus(next)
    }

    package var registeredCount: Int { targets.count }
}

@MainActor
package final class WindowServices {
    package let focus = FocusSystem()
    package let shortcuts = ShortcutRegistry()
    package var clipboard: (any PlatformClipboard)?
    var urlHandlers: [OpenURLHandlerState] = []
    package var pointerModifiers: KeyModifiers = []
    package var popups: PopupPresenting?
    package let presentations = PresentationCenter()
    package let toolbar = WindowToolbarModel()
    package weak var menuBar: MenuBarController?
    package weak var sidebar: SidebarController?
    package let contextMenus = ContextMenuCenter()
    package let tooltips = TooltipCenter()
    package var lastEventTime: TimeInterval = 0
    package var requestDisplay: () -> Void = {}

    private var timers: [ObjectIdentifier: (deadline: TimeInterval, fire: (TimeInterval) -> Void)] = [:]

    package init(clipboard: (any PlatformClipboard)? = nil) { self.clipboard = clipboard }

    package func setTimer(_ owner: AnyObject, at deadline: TimeInterval?, fire: @escaping (TimeInterval) -> Void) {
        let id = ObjectIdentifier(owner)
        if let deadline { timers[id] = (deadline, fire) } else { timers[id] = nil }
    }

    package var nextTimerDeadline: TimeInterval? { timers.values.map(\.deadline).min() }

    package func fireTimers(now: TimeInterval) {
        let due = timers.filter { $0.value.deadline <= now + 1e-9 }
        for (id, t) in due {
            timers[id] = nil
            t.fire(now)
        }
    }
}

@MainActor
package protocol PopupPresenting: AnyObject {
    func presentPopup(content: AnyView, origin: CGPoint, anchor: CGRect?, minWidth: CGFloat, chrome: PopupChrome,
                      fallbackKeys: ((KeyEvent) -> Bool)?, onDismiss: @escaping () -> Void) -> PopupHandle?
}

package enum PopupChrome { case menu, plain }

extension PopupPresenting {
    func presentPopup(content: AnyView, origin: CGPoint, minWidth: CGFloat, chrome: PopupChrome,
                      fallbackKeys: ((KeyEvent) -> Bool)?, onDismiss: @escaping () -> Void) -> PopupHandle? {
        presentPopup(content: content, origin: origin, anchor: nil, minWidth: minWidth, chrome: chrome, fallbackKeys: fallbackKeys,
                     onDismiss: onDismiss)
    }

    func presentPopup(content: AnyView, origin: CGPoint, minWidth: CGFloat, onDismiss: @escaping () -> Void) -> PopupHandle? {
        presentPopup(content: content, origin: origin, minWidth: minWidth, chrome: .menu, fallbackKeys: nil, onDismiss: onDismiss)
    }

    func presentPopup(content: AnyView, origin: CGPoint, minWidth: CGFloat, chrome: PopupChrome,
                      onDismiss: @escaping () -> Void) -> PopupHandle? {
        presentPopup(content: content, origin: origin, minWidth: minWidth, chrome: chrome, fallbackKeys: nil, onDismiss: onDismiss)
    }
}

@MainActor
package final class PopupHandle {
    let dismissAction: () -> Void
    package private(set) var isDismissed = false
    package init(dismiss: @escaping () -> Void) { dismissAction = dismiss }
    package func dismiss() {
        guard !isDismissed else { return }
        isDismissed = true
        dismissAction()
    }

    package func markDismissed() { isDismissed = true }
}

private enum WindowServicesKey: EnvironmentKey {
    static let defaultValue: WindowServices? = nil
}

extension EnvironmentValues {
    package var _windowServices: WindowServices? {
        get { self[WindowServicesKey.self] }
        set { self[WindowServicesKey.self] = newValue }
    }
}

final class FocusableState {
    var registered: WindowServices?
}

struct FocusableModifier: PrimitiveModifier {
    let isFocusable: Bool

    private func sync(_ node: ViewNode) {
        let state = (node.primitiveState as? FocusableState) ?? FocusableState()
        node.primitiveState = state
        let services = node.environment._windowServices
        if isFocusable, let services {
            services.focus.register(node, bindings: node.environment._focusBindings, client: nil)
            state.registered = services
        } else {
            state.registered?.focus.unregister(node)
            state.registered = nil
        }
    }

    func _inserted(node: ViewNode) { sync(node) }
    func _updated(old: FocusableModifier, node: ViewNode) { sync(node) }
    func _removed(node: ViewNode) { (node.primitiveState as? FocusableState)?.registered?.focus.unregister(node) }
}
