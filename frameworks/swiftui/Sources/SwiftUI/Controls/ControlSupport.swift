import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

extension Color {
    init(swiftcodeHex hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

struct ControlPalette {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    var fill: Color { dark ? Color(swiftcodeHex: 0x787880, opacity: 0x5C / 255) : Color(swiftcodeHex: 0x787880, opacity: 0x33 / 255) }
    var subtleFill: Color { dark ? Color(swiftcodeHex: 0x787880, opacity: 0.32) : Color(swiftcodeHex: 0x787880, opacity: 0.16) }
    var separator: Color { dark ? Color(swiftcodeHex: 0x545458, opacity: 0x80 / 255) : Color(swiftcodeHex: 0x3C3C43, opacity: 0x1F / 255) }
    var outline: Color { dark ? Color(swiftcodeHex: 0xEBEBF5, opacity: 0.3) : Color(swiftcodeHex: 0x3C3C43, opacity: 0.3) }
    var groupedBackground: Color { dark ? Color(swiftcodeHex: 0x000000) : Color(swiftcodeHex: 0xF2F2F7) }
    var groupedRow: Color { dark ? Color(swiftcodeHex: 0x1C1C1E) : Color(swiftcodeHex: 0xFFFFFF) }
    var fieldBackground: Color { dark ? Color(swiftcodeHex: 0x1C1C1E) : Color(swiftcodeHex: 0xFFFFFF) }
    var menuBackground: Color { dark ? Color(swiftcodeHex: 0x2C2C2E) : Color(swiftcodeHex: 0xFFFFFF) }
    var placeholder: Color { dark ? Color(swiftcodeHex: 0xEBEBF5, opacity: 0x4C / 255) : Color(swiftcodeHex: 0x3C3C43, opacity: 0x4C / 255) }
    var secondaryLabel: Color { dark ? Color(swiftcodeHex: 0xEBEBF5, opacity: 0x99 / 255) : Color(swiftcodeHex: 0x3C3C43, opacity: 0x99 / 255) }
    var switchOff: Color { dark ? Color(swiftcodeHex: 0x39393D) : Color(swiftcodeHex: 0xE5E5EA) }
    var thumb: Color { dark ? Color(swiftcodeHex: 0xF2F2F7) : Color(swiftcodeHex: 0xFFFFFF) }
    var thumbBorder: Color { dark ? Color(swiftcodeHex: 0x000000, opacity: 0.25) : Color(swiftcodeHex: 0x000000, opacity: 0.12) }
    var segmentSelected: Color { dark ? Color(swiftcodeHex: 0x636366) : Color(swiftcodeHex: 0xFFFFFF) }
    var menuHighlight: Color { dark ? Color(swiftcodeHex: 0xFFFFFF, opacity: 0.12) : Color(swiftcodeHex: 0x000000, opacity: 0.07) }
    var indicator: Color { dark ? Color(swiftcodeHex: 0xFFFFFF, opacity: 0.45) : Color(swiftcodeHex: 0x000000, opacity: 0.38) }
    var rowSelectionOpacity: Double { dark ? 0.35 : 0.22 }
    var plainBackground: Color { dark ? Color(swiftcodeHex: 0x000000) : Color(swiftcodeHex: 0xFFFFFF) }
    var sidebarBackground: Color { dark ? Color(swiftcodeHex: 0x1C1C1E) : Color(swiftcodeHex: 0xF2F2F7) }
    var barBackground: Color { dark ? Color(swiftcodeHex: 0x1C1C1E, opacity: 0.94) : Color(swiftcodeHex: 0xF9F9F9, opacity: 0.94) }
    var dimming: Color { dark ? Color(swiftcodeHex: 0x000000, opacity: 0.48) : Color(swiftcodeHex: 0x000000, opacity: 0.2) }
    var sheetBackground: Color { dark ? Color(swiftcodeHex: 0x1C1C1E) : Color(swiftcodeHex: 0xFFFFFF) }
    var alertBackground: Color { dark ? Color(swiftcodeHex: 0x2C2C2E) : Color(swiftcodeHex: 0xF2F2F2) }
    var destructive: Color { .red }
}

private enum LabelsHiddenKey: EnvironmentKey { static let defaultValue = false }
private enum InFormKey: EnvironmentKey { static let defaultValue = false }
private enum InMenuKey: EnvironmentKey { static let defaultValue = false }
private enum FormStyleKindKey: EnvironmentKey { static let defaultValue = 0 }
private enum FormColumnWidthKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }

extension EnvironmentValues {
    package var _labelsHidden: Bool {
        get { self[LabelsHiddenKey.self] }
        set { self[LabelsHiddenKey.self] = newValue }
    }

    package var _inForm: Bool {
        get { self[InFormKey.self] }
        set { self[InFormKey.self] = newValue }
    }

    package var _formStyleKind: Int {
        get { self[FormStyleKindKey.self] }
        set { self[FormStyleKindKey.self] = newValue }
    }

    package var _formColumnWidth: CGFloat? {
        get { self[FormColumnWidthKey.self] }
        set { self[FormColumnWidthKey.self] = newValue }
    }

    package var _inMenu: Bool {
        get { self[InMenuKey.self] }
        set { self[InMenuKey.self] = newValue }
    }
}

extension View {
    public func labelsHidden() -> some View { environment(\._labelsHidden, true) }
}

struct ControlRowLayout: Layout {
    var spacing: CGFloat = 8
    var controlLeading = false
    var columnWidth: CGFloat?

    private func parts(_ s: Subviews) -> (label: LayoutSubview?, control: LayoutSubview?) {
        switch s.count {
        case 0: return (nil, nil)
        case 1: return (nil, s[s.startIndex])
        default: return controlLeading ? (s[s.startIndex + 1], s[s.startIndex]) : (s[s.startIndex], s[s.startIndex + 1])
        }
    }

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing { ViewSpacing() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (label, control) = parts(subviews)
        if let column = columnWidth { return columnsSize(label, control, column: column, proposal: proposal) }
        let c = control?.sizeThatFits(.unspecified) ?? .zero
        guard let label else { return c }
        if controlLeading {
            let w = proposal.width.map { max(0, $0 - c.width - spacing) }
            let l = label.sizeThatFits(ProposedViewSize(width: w, height: proposal.height))
            return CGSize(width: c.width + spacing + l.width, height: max(c.height, l.height))
        }
        let width: CGFloat
        let labelWidth: CGFloat?
        if let pw = proposal.width {
            let minimum = label.sizeThatFits(ProposedViewSize(width: 0, height: proposal.height)).width + spacing + c.width
            width = max(pw, minimum)
            labelWidth = max(0, width - spacing - c.width)
        } else {
            labelWidth = nil
            width = label.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)).width + spacing + c.width
        }
        let l = label.sizeThatFits(ProposedViewSize(width: labelWidth, height: proposal.height))
        return CGSize(width: width, height: max(c.height, l.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (label, control) = parts(subviews)
        if let column = columnWidth {
            placeColumns(label, control, column: column, in: bounds)
            return
        }
        let c = control?.sizeThatFits(.unspecified) ?? .zero
        if controlLeading {
            control?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(c))
            let w = max(0, bounds.width - c.width - spacing)
            label?.place(at: CGPoint(x: bounds.minX + c.width + spacing, y: bounds.midY), anchor: .leading,
                         proposal: ProposedViewSize(width: w, height: bounds.height))
            return
        }
        control?.place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(c))
        let w = max(0, bounds.width - c.width - spacing)
        label?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                     proposal: ProposedViewSize(width: w, height: bounds.height))
    }

    private func columnsParts(_ label: LayoutSubview?, _ control: LayoutSubview?, column: CGFloat,
                              proposal: ProposedViewSize) -> (label: CGSize, control: CGSize, title: CGSize) {
        let c = control?.sizeThatFits(.unspecified) ?? .zero
        if controlLeading {
            let room = proposal.width.map { max(0, $0 - column - spacing - c.width - spacing) }
            let t = label?.sizeThatFits(ProposedViewSize(width: room, height: nil)) ?? .zero
            return (.zero, c, t)
        }
        let l = label?.sizeThatFits(ProposedViewSize(width: column, height: nil)) ?? .zero
        return (CGSize(width: min(l.width, column), height: l.height), c, .zero)
    }

    private func columnsSize(_ label: LayoutSubview?, _ control: LayoutSubview?, column: CGFloat,
                             proposal: ProposedViewSize) -> CGSize {
        let p = columnsParts(label, control, column: column, proposal: proposal)
        let title = p.title.width > 0 ? spacing + p.title.width : 0
        let width = column + spacing + p.control.width + title
        return CGSize(width: max(width, proposal.width ?? 0), height: max(p.label.height, p.control.height, p.title.height))
    }

    private func placeColumns(_ label: LayoutSubview?, _ control: LayoutSubview?, column: CGFloat, in bounds: CGRect) {
        let p = columnsParts(label, control, column: column, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        let x = bounds.minX + column + spacing
        control?.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(p.control))
        if controlLeading {
            label?.place(at: CGPoint(x: x + p.control.width + spacing, y: bounds.midY), anchor: .leading,
                         proposal: ProposedViewSize(width: p.title.width, height: p.title.height))
        } else {
            label?.place(at: CGPoint(x: bounds.minX + column, y: bounds.midY), anchor: .trailing,
                         proposal: ProposedViewSize(width: p.label.width, height: p.label.height))
        }
    }
}

struct ColumnLabelAlignment: ViewModifier {
    let inColumn: Bool
    @Environment(\.multilineTextAlignment) private var current

    func body(content: Content) -> some View {
        content.environment(\.multilineTextAlignment, inColumn ? .trailing : current)
    }
}

struct FillWidthLayout: Layout {
    var height: CGFloat
    var idealWidth: CGFloat = 0

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing { ViewSpacing() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: max(0, proposal.width ?? idealWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for s in subviews {
            s.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

struct ControlPressGesture: Gesture, PrimitiveGesture {
    typealias Value = Void
    typealias Body = Never
    let onPressed: @MainActor (Bool) -> Void
    let onAction: @MainActor () -> Void

    func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        PressRecognizer(context: context, onPressed: onPressed, onAction: onAction)
    }
}

struct ControlTrackGesture: Gesture, PrimitiveGesture {
    typealias Value = Void
    typealias Body = Never
    var accepts: @MainActor (CGPoint) -> Bool = { _ in true }
    let handler: @MainActor (PointerTrackRecognizer.Event) -> Void

    func _makeRecognizer(context: GestureContext) -> GestureRecognizer {
        PointerTrackRecognizer(context: context, accepts: accepts, handler: handler)
    }
}

typealias ControlKeyHandler = @MainActor (KeyEvent) -> Bool

struct ControlFocusModifier: PrimitiveModifier {
    let isFocused: Binding<Bool>
    let onKey: ControlKeyHandler
    var ref: NodeRef?

    private final class Registration {
        var services: WindowServices?
    }

    private func sync(_ node: ViewNode) {
        let reg = (node.primitiveState as? Registration) ?? Registration()
        node.primitiveState = reg
        ref?.node = node
        let env = node.environment
        if env.isEnabled, let services = env._windowServices {
            let binding = isFocused
            services.focus.register(node, bindings: env._focusBindings, client: nil, keyHandler: onKey,
                                    onFocusChange: { f in if binding.wrappedValue != f { binding.wrappedValue = f } })
            reg.services = services
            let focused = services.focus.isFocused(node)
            if isFocused.wrappedValue != focused { isFocused.wrappedValue = focused }
        } else {
            reg.services?.focus.unregister(node)
            reg.services = nil
            if isFocused.wrappedValue { isFocused.wrappedValue = false }
        }
    }

    func _inserted(node: ViewNode) { sync(node) }
    func _updated(old: ControlFocusModifier, node: ViewNode) { sync(node) }
    func _removed(node: ViewNode) { (node.primitiveState as? Registration)?.services?.focus.unregister(node) }
}

extension View {
    func controlFocus(_ isFocused: Binding<Bool>, ref: NodeRef? = nil, onKey: @escaping ControlKeyHandler) -> some View {
        modifier(ControlFocusModifier(isFocused: isFocused, onKey: onKey, ref: ref))
    }

    func focusRing<S: Shape>(_ visible: Bool, _ shape: S) -> some View {
        overlay {
            if visible {
                shape.stroke(.tint.opacity(0.55), lineWidth: 2.5).padding(-3).allowsHitTesting(false)
            }
        }
    }
}

@MainActor
func isActivationKey(_ k: KeyEvent) -> Bool {
    guard k.isDown, !k.modifiers.contains(.control), !k.modifiers.contains(.command) else { return false }
    return k.key == .space || k.key == .return
}

final class ShortcutOwner {}

struct ShortcutRegistrationModifier: PrimitiveModifier {
    let owner: ShortcutOwner
    let action: @MainActor () -> Void

    private final class Registration { var services: WindowServices? }

    private func sync(_ node: ViewNode) {
        let reg = (node.primitiveState as? Registration) ?? Registration()
        node.primitiveState = reg
        let env = node.environment
        if let shortcut = env._keyboardShortcut, let services = env._windowServices {
            let action = action
            services.shortcuts.register(owner, ShortcutRegistry.Entry(shortcut: shortcut, action: { action() },
                                                                       isEnabled: { [weak node] in
                                                                           guard let node, node.isAlive else { return false }
                                                                           return node.environment.isEnabled && !node.isInSuspendedSubtree
                                                                       },
                                                                       isCommand: env._inCommandHost))
            reg.services = services
        } else {
            reg.services?.shortcuts.unregister(owner)
            reg.services = nil
        }
    }

    func _inserted(node: ViewNode) { sync(node) }
    func _updated(old: ShortcutRegistrationModifier, node: ViewNode) { sync(node) }
    func _removed(node: ViewNode) { (node.primitiveState as? Registration)?.services?.shortcuts.unregister(owner) }
}

struct ErasedContent: View {
    let view: AnyView
    init(_ v: some View) { view = AnyView(v) }
    init(any v: any View) { view = AnyView(_fromValue: v) ?? AnyView(EmptyView()) }
    var body: some View { view }
}
