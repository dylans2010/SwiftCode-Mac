import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

public enum TextSurfaceCommand: String, CaseIterable, Sendable {
    case undo, redo, cut, copy, paste, delete, selectAll

    init(_ c: StandardEditCommand) {
        switch c {
        case .undo: self = .undo
        case .redo: self = .redo
        case .cut: self = .cut
        case .copy: self = .copy
        case .paste: self = .paste
        case .delete: self = .delete
        case .selectAll: self = .selectAll
        }
    }
}

@MainActor
public protocol TextSurfaceClient: AnyObject {
    func surfaceConnected(_ connection: TextSurfaceConnection?)
    func surfaceInsertText(_ text: String)
    func surfaceSetMarkedText(_ text: String, cursor: Int)
    func surfaceHandleKey(_ event: KeyEvent) -> Bool
    var surfaceCaretRect: CGRect { get }
    func surfaceFocusChanged(_ focused: Bool)
    func surfaceCanPerform(_ command: TextSurfaceCommand) -> Bool
    func surfacePerform(_ command: TextSurfaceCommand)
}

@MainActor
public final class TextSurfaceConnection {
    private let services: WindowServices
    private weak var node: ViewNode?
    private let client: () -> (any TextInputClient)?

    init(services: WindowServices, node: ViewNode, client: @escaping () -> (any TextInputClient)?) {
        self.services = services
        self.node = node
        self.client = client
    }

    public var clipboardText: String? {
        get { services.clipboard?.text }
        set { services.clipboard?.text = newValue }
    }

    public var hasClipboardText: Bool { services.clipboard?.hasText ?? false }

    public var pointerModifiers: KeyModifiers { services.pointerModifiers }

    public var now: TimeInterval { node?.graph.timeSource.now ?? 0 }

    public func setTimer(_ owner: AnyObject, after delay: TimeInterval?, fire: @escaping @MainActor () -> Void) {
        services.setTimer(owner, at: delay.map { now + $0 }) { _ in fire() }
    }

    public func setNeedsDisplay() { services.requestDisplay() }

    public func caretMoved() {
        guard let c = client(), services.focus.focusedClient === c else { return }
        services.focus.onTextClientChanged(c)
    }
}

final class TextSurfaceAdapter: TextInputClient {
    weak var client: (any TextSurfaceClient)?
    weak var services: WindowServices?
    var connection: TextSurfaceConnection?

    func insertText(_ text: String) { client?.surfaceInsertText(text) }
    func setMarkedText(_ text: String, cursor: Int) { client?.surfaceSetMarkedText(text, cursor: cursor) }
    func handleKey(_ event: KeyEvent) -> Bool { client?.surfaceHandleKey(event) ?? false }
    var caretRect: CGRect { client?.surfaceCaretRect ?? .zero }
    func focusChanged(_ focused: Bool) { client?.surfaceFocusChanged(focused) }
    func canPerform(_ command: StandardEditCommand, clipboard: (any PlatformClipboard)?) -> Bool {
        client?.surfaceCanPerform(TextSurfaceCommand(command)) ?? false
    }
    func perform(_ command: StandardEditCommand, clipboard: (any PlatformClipboard)?) {
        client?.surfacePerform(TextSurfaceCommand(command))
    }
}

struct TextSurfaceModifier: PrimitiveModifier {
    let client: any TextSurfaceClient
    let isEnabled: Bool

    private func sync(_ node: ViewNode) {
        let adapter = (node.primitiveState as? TextSurfaceAdapter) ?? TextSurfaceAdapter()
        node.primitiveState = adapter
        guard let services = node.environment._windowServices else { return }
        let changed = adapter.client !== client
        adapter.client = client
        adapter.services = services
        if isEnabled {
            services.focus.register(node, bindings: node.environment._focusBindings, client: adapter)
        } else {
            services.focus.unregister(node)
        }
        if changed || adapter.connection == nil {
            let c = TextSurfaceConnection(services: services, node: node) { [weak adapter] in adapter }
            adapter.connection = c
            client.surfaceConnected(c)
        }
    }

    func _inserted(node: ViewNode) { sync(node) }
    func _updated(old: TextSurfaceModifier, node: ViewNode) { sync(node) }
    func _removed(node: ViewNode) {
        guard let a = node.primitiveState as? TextSurfaceAdapter else { return }
        a.services?.focus.unregister(node)
        a.client?.surfaceConnected(nil)
        a.connection = nil
    }
}

extension TextSurfaceModifier: GraphInputComparable {
    nonisolated func _isGraphInputEqual(to other: Any) -> Bool { false }
}

extension View {
    public func textSurface(_ client: any TextSurfaceClient, isEnabled: Bool = true) -> some View {
        modifier(TextSurfaceModifier(client: client, isEnabled: isEnabled))
    }
}

public enum TextSurfacePointerEvent: Equatable, Sendable {
    case down(CGPoint, time: TimeInterval)
    case moved(CGPoint, time: TimeInterval)
    case up(CGPoint, time: TimeInterval)
    case cancelled
}

extension View {
    public func textSurfacePointer(_ handler: @escaping @MainActor (TextSurfacePointerEvent) -> Void) -> some View {
        highPriorityGesture(ControlTrackGesture { e in
            switch e {
            case .down(let p, let t): handler(.down(p, time: t))
            case .moved(let p, let t): handler(.moved(p, time: t))
            case .up(let p, let t): handler(.up(p, time: t))
            case .cancelled: handler(.cancelled)
            }
        })
    }
}

extension View {
    public func textSurfaceScroll(_ action: @escaping @MainActor (CGSize, CGPoint) -> Bool) -> some View {
        _onScrollWheel { d, p in MainActor.assumeIsolated { action(d, p) } }
    }
}

@MainActor
public enum ApplicationTermination {
    public static var shouldTerminate: (() -> Bool)?
}
