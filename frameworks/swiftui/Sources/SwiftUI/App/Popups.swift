import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor
final class WindowPopupPresenter: PopupPresenting {
    weak var host: AppHost?
    weak var window: WindowHost?

    init(host: AppHost, window: WindowHost) {
        self.host = host
        self.window = window
    }

    func presentPopup(content: AnyView, origin: CGPoint, anchor: CGRect?, minWidth: CGFloat, chrome: PopupChrome,
                      fallbackKeys: ((KeyEvent) -> Bool)?, onDismiss: @escaping () -> Void) -> PopupHandle? {
        guard let host, let window else { return nil }
        return host.presentPopup(from: window, content: content, origin: origin, anchor: anchor, minWidth: minWidth, chrome: chrome,
                                 fallbackKeys: fallbackKeys, onDismiss: onDismiss)
    }
}

package struct OverlayPopup: Identifiable {
    package let id: Int
    let content: AnyView
    let origin: CGPoint
    let size: CGSize
}

struct OverlayPopupLayer: View {
    let items: [OverlayPopup]
    let windowSize: CGSize
    @Environment(\._dismissPopup) private var dismissAll

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(ControlPressGesture(onPressed: { p in if p { dismissAll?() } }, onAction: {}))
            ForEach(items) { item in
                item.content
                    .frame(width: item.size.width, height: item.size.height)
                    .offset(x: item.origin.x, y: item.origin.y)
            }
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .topLeading)
    }
}

extension AppHost {
    private func chain(_ w: WindowHost) -> [WindowHost] {
        var out: [WindowHost] = []
        var c: WindowHost? = w
        while let x = c {
            out.append(x)
            c = x.isPopup ? x.popupOwner : nil
        }
        return out
    }

    private func rootPopup(_ w: WindowHost) -> WindowHost {
        var r = w
        while let o = r.popupOwner, o.isPopup { r = o }
        return r
    }

    func presentPopup(from owner: WindowHost, content: AnyView, origin requested: CGPoint, anchor: CGRect? = nil, minWidth: CGFloat,
                      chrome kind: PopupChrome = .menu, fallbackKeys: ((KeyEvent) -> Bool)? = nil,
                      onDismiss: @escaping () -> Void) -> PopupHandle? {
        for p in windows where p.isPopup && p.popupOwner === owner { closePopup(p) }
        let chrome = kind == .menu ? AnyView(MenuChrome(content: content)) : content
        var env = owner.graph.environment
        env._windowServices = nil
        env._dismissPopup = nil
        var measureMain: WindowHost = owner
        while measureMain.isPopup, let o = measureMain.popupOwner { measureMain = o }
        env._popupOwnerServices = measureMain.services
        let symbols = owner.graph.layout?.symbols ?? StubSymbolProvider()
        let measure = ViewGraph(rootView: chrome, environment: env,
                                layout: HostLayout(.proposal(.unspecified), symbols: symbols))
        measure.update()
        var size = measure.layoutResult?.size ?? CGSize(width: 160, height: 100)
        measure.setRootView(EmptyView())
        measure.update()
        size.width = max(size.width, minWidth).rounded(.up)
        size.height = size.height.rounded(.up)
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        var offset = CGPoint.zero
        var main: WindowHost = owner
        while main.isPopup, let o = main.popupOwner {
            offset.x += main.popupOrigin.x
            offset.y += main.popupOrigin.y
            main = o
        }
        let placed = PopupPlacement.origin(requested.offsetBy(offset), size: size, anchor: anchor.map { $0.offsetBy(dx: offset.x, dy: offset.y) },
                                           bounds: main.size)
        let origin = CGPoint(x: placed.x - offset.x, y: placed.y - offset.y)

        let config = WindowConfiguration(title: "", size: size, resizable: false, vulkan: false,
                                         highPixelDensity: true, popupParent: owner.platform.id, popupOrigin: origin)
        guard let pw = try? backend.makeWindow(config) else {
            log?("pop-up window refused; showing it inside the window")
            return presentOverlay(in: owner, content: chrome, origin: origin, size: size, onDismiss: onDismiss)
        }
        log?("pop-up \(pw.id) of \(owner.platform.id) at (\(origin.x), \(origin.y)) \(size.width)x\(size.height)")
        let box = WeakWindowBox()
        env = owner.graph.environment
        env._popupOwnerServices = main.services
        env._dismissPopup = { [weak self] in
            guard let self, let w = box.window else { return }
            self.closePopup(self.rootPopup(w))
        }
        let w = WindowHost(platform: pw, sceneIndex: owner.sceneIndex, sceneID: nil, content: chrome,
                           environment: env, clock: clock, presenter: makePresenter(pw))
        box.window = w
        w.isPopup = true
        w.popupOwner = owner
        w.popupOrigin = origin
        w.popupOnDismiss = onDismiss
        w.services.clipboard = backend.clipboard
        w.services.popups = WindowPopupPresenter(host: self, window: w)
        w.onPopupKey = { [weak self, weak w] k in
            guard let self, let w else { return false }
            switch k.key {
            case .escape:
                self.closePopup(w)
            case .leftArrow where w.popupOwner?.isPopup == true:
                self.closePopup(w)
            case .downArrow:
                w.services.focus.focusNext(in: w.graph.root)
            case .upArrow:
                w.services.focus.focusNext(in: w.graph.root, reverse: true)
            default:
                return false
            }
            return true
        }
        let handle = PopupHandle { [weak self, weak w] in
            guard let self, let w else { return }
            self.closePopup(w)
        }
        w.popupHandle = handle
        w.onPopupFallbackKey = fallbackKeys
        addWindow(w)
        w.setPhase(appPhase)
        w.update()
        return handle
    }

    func closePopup(_ w: WindowHost) {
        guard w.isPopup, windows.contains(where: { $0 === w }) else { return }
        for p in windows where p.isPopup && p.popupOwner === w { closePopup(p) }
        log?("pop-up \(w.platform.id) closed")
        removeWindow(w)
        w.popupHandle?.markDismissed()
        w.teardown()
        w.platform.close()
        let action = w.popupOnDismiss
        w.popupOnDismiss = nil
        if let owner = w.popupOwner, windows.contains(where: { $0 === owner }) { owner.platform.activate() }
        action?()
    }

    func closePopups(outside id: PlatformWindowID, at point: CGPoint) -> Bool {
        guard let target = window(for: id) else { return false }
        let keep = chain(target)
        var closed = false
        for p in windows where p.isPopup && !keep.contains(where: { $0 === p }) {
            guard windows.contains(where: { $0 === p }) else { continue }
            closePopup(p)
            closed = true
        }
        return closed
    }

    private func presentOverlay(in owner: WindowHost, content: AnyView, origin: CGPoint, size: CGSize,
                                onDismiss: @escaping () -> Void) -> PopupHandle {
        let ws = owner.size
        let o = CGPoint(x: max(0, min(origin.x, ws.width - size.width)), y: max(0, min(origin.y, ws.height - size.height)))
        let id = (owner.overlayPopups.map(\.id).max() ?? 0) + 1
        let handle = PopupHandle { [weak owner] in
            guard let owner else { return }
            owner.overlayPopups.removeAll { $0.id == id }
            onDismiss()
        }
        let dismiss: @MainActor () -> Void = { [weak owner] in
            guard let owner, !owner.overlayPopups.isEmpty else { return }
            owner.overlayPopups = []
            handle.markDismissed()
            onDismiss()
        }
        let item = OverlayPopup(id: id, content: AnyView(content.environment(\._dismissPopup, dismiss)), origin: o, size: size)
        owner.overlayPopups.append(item)
        owner.graph.updateEnvironment { $0._dismissPopup = dismiss }
        return handle
    }
}

@MainActor
final class WeakWindowBox {
    weak var window: WindowHost?
}

enum PopupPlacement {
    static func origin(_ o: CGPoint, size: CGSize, anchor: CGRect?, bounds: CGSize) -> CGPoint {
        var p = o
        let beside = anchor.map { o.x >= $0.maxX - 4 && o.y < $0.maxY } ?? false
        if p.y + size.height > bounds.height {
            if let a = anchor, !beside {
                let gap = max(0, o.y - a.maxY)
                let above = a.minY - gap - size.height
                p.y = above >= 0 ? above : max(0, bounds.height - size.height)
            } else {
                p.y = max(0, bounds.height - size.height)
            }
        }
        if p.x + size.width > bounds.width {
            if let a = anchor, beside, a.minX - size.width + 2 >= 0 {
                p.x = a.minX - size.width + 2
            } else {
                p.x = max(0, bounds.width - size.width)
            }
        }
        return CGPoint(x: max(0, p.x), y: max(0, p.y))
    }
}

private extension CGPoint {
    func offsetBy(_ d: CGPoint) -> CGPoint { CGPoint(x: x + d.x, y: y + d.y) }
}
