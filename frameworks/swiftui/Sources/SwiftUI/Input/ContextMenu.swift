import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
package final class ContextMenuCenter {
    final class Registration {
        weak var node: ViewNode?
        var items: () -> AnyView?
        init(node: ViewNode, items: @escaping () -> AnyView?) {
            self.node = node
            self.items = items
        }
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]
    var pendingPress: (pointer: Int, start: CGPoint, deadline: TimeInterval)?
    package private(set) var openedCount = 0

    package init() {}

    func register(_ node: ViewNode, items: @escaping () -> AnyView?) {
        registrations[ObjectIdentifier(node)] = Registration(node: node, items: items)
    }

    func unregister(_ node: ViewNode) { registrations[ObjectIdentifier(node)] = nil }

    func items(on chain: [ViewNode]) -> AnyView? {
        for n in chain.reversed() {
            if let r = registrations[ObjectIdentifier(n)], r.node === n, !n.isInSuspendedSubtree, let v = r.items() {
                return v
            }
        }
        return nil
    }

    var isEmpty: Bool { registrations.isEmpty }

    func noteOpened() { openedCount += 1 }
}

struct ContextMenuModifier: PrimitiveModifier {
    let items: @MainActor () -> AnyView?

    private final class State { weak var center: ContextMenuCenter? }

    private func sync(_ node: ViewNode) {
        let s = (node.primitiveState as? State) ?? State()
        node.primitiveState = s
        guard let center = node.environment._windowServices?.contextMenus else { return }
        s.center = center
        center.register(node, items: items)
    }

    func _inserted(node: ViewNode) { sync(node) }
    func _updated(old: ContextMenuModifier, node: ViewNode) { sync(node) }
    func _removed(node: ViewNode) { (node.primitiveState as? State)?.center?.unregister(node) }
}

extension View {
    public func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View {
        let items = AnyView(menuItems())
        return modifier(ContextMenuModifier(items: { items }))
    }

    public func contextMenu<M: View, P: View>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some View {
        contextMenu(menuItems: menuItems)
    }

    public func contextMenu<I: Hashable, M: View>(forSelectionType itemType: I.Type = I.self,
                                                  @ViewBuilder menu: @escaping (Set<I>) -> M,
                                                  primaryAction: ((Set<I>) -> Void)? = nil) -> some View {
        let make = ListContextMenu(make: { ids in
            let set = Set(ids.compactMap { $0.base as? I })
            return AnyView(menu(set))
        })
        return environment(\._listContextMenu, make)
            .modifier(ContextMenuModifier(items: { AnyView(menu([])) }))
    }
}

struct ListContextMenu {
    let make: @MainActor ([AnyHashable]) -> AnyView
}

private enum ListContextMenuKey: EnvironmentKey { static let defaultValue: ListContextMenu? = nil }

extension EnvironmentValues {
    var _listContextMenu: ListContextMenu? {
        get { self[ListContextMenuKey.self] }
        set { self[ListContextMenuKey.self] = newValue }
    }
}

extension WindowHost {
    @discardableResult
    package func openContextMenu(at point: CGPoint) -> Bool {
        if graph.needsUpdate { update() }
        let chain = gestures.hitPath(at: point)
        guard let items = services.contextMenus.items(on: chain), let popups = services.popups else { return false }
        gestures.cancel()
        guard popups.presentPopup(content: items, origin: point, anchor: CGRect(origin: point, size: .zero), minWidth: 160, chrome: .menu,
                                  fallbackKeys: nil, onDismiss: {}) != nil else {
            return false
        }
        services.contextMenus.noteOpened()
        return true
    }

    func openContextMenuForFocus() -> Bool {
        guard let focused = services.focus.focusedNode else { return false }
        var chain: [ViewNode] = []
        var n: ViewNode? = focused
        while let x = n {
            chain.insert(x, at: 0)
            n = x.parent
        }
        guard let items = services.contextMenus.items(on: chain), let popups = services.popups else { return false }
        let f = HitTesting.frame(of: focused, mirrorWidth: nil) ?? .zero
        guard popups.presentPopup(content: items, origin: CGPoint(x: f.minX + 8, y: f.minY + 8), minWidth: 160, chrome: .menu,
                                  onDismiss: {}) != nil else { return false }
        services.contextMenus.noteOpened()
        return true
    }

    func trackContextPress(_ p: PointerEvent) {
        let center = services.contextMenus
        guard !center.isEmpty else { return }
        switch p.phase {
        case .down where p.kind != .mouse:
            center.pendingPress = (p.pointer, p.location, p.timestamp + 0.5)
            services.setTimer(center, at: p.timestamp + 0.5) { [weak self] _ in
                guard let self, let pending = self.services.contextMenus.pendingPress else { return }
                self.services.contextMenus.pendingPress = nil
                self.openContextMenu(at: pending.start)
            }
        case .moved:
            if let pending = center.pendingPress, pending.pointer == p.pointer,
               hypot(p.location.x - pending.start.x, p.location.y - pending.start.y) > 10 {
                center.pendingPress = nil
                services.setTimer(center, at: nil) { _ in }
            }
        case .up, .cancelled:
            if center.pendingPress?.pointer == p.pointer {
                center.pendingPress = nil
                services.setTimer(center, at: nil) { _ in }
            }
        default:
            break
        }
    }
}
