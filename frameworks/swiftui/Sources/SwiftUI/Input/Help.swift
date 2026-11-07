import Foundation
import Observation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

enum TooltipMetrics {
    static let delay: TimeInterval = 0.8
    static let grace: TimeInterval = 0.5
    static let offset: CGFloat = 18
    static let maxWidth: CGFloat = 320
}

@MainActor
@Observable
package final class TooltipCenter {
    package struct Tip: Equatable {
        package let text: String
        package let point: CGPoint
        package let owner: ObjectIdentifier
    }

    package private(set) var current: Tip?
    @ObservationIgnored var lastHidden: TimeInterval = -.infinity

    package init() {}

    func show(_ tip: Tip) { if current != tip { current = tip } }

    func hide(owner: ObjectIdentifier? = nil, at time: TimeInterval) {
        guard let c = current, owner == nil || c.owner == owner else { return }
        current = nil
        lastHidden = time
    }

    package func dismiss() {
        current = nil
        lastHidden = -.infinity
    }
}

@MainActor
final class HelpState: HoverHandling {
    var text: String
    weak var services: WindowServices?
    private var inside = false
    private var point = CGPoint.zero

    init(text: String) { self.text = text }

    nonisolated func hover(location: CGPoint?, frame: CGRect) {
        MainActor.assumeIsolated { hoverOnMain(location: location, frame: frame) }
    }

    private func hoverOnMain(location: CGPoint?, frame: CGRect) {
        guard let services else { return }
        let id = ObjectIdentifier(self)
        let now = services.lastEventTime
        if let l = location {
            point = CGPoint(x: frame.minX + l.x, y: frame.minY + l.y)
            guard !inside else { return }
            inside = true
            guard !text.isEmpty else { return }
            if now - services.tooltips.lastHidden < TooltipMetrics.grace {
                services.tooltips.show(.init(text: text, point: point, owner: id))
            } else {
                services.setTimer(self, at: now + TooltipMetrics.delay) { [weak self] _ in self?.fire() }
            }
        } else if inside {
            inside = false
            services.setTimer(self, at: nil) { _ in }
            services.tooltips.hide(owner: id, at: now)
        }
    }

    private func fire() {
        guard inside, !text.isEmpty, let services else { return }
        services.tooltips.show(.init(text: text, point: point, owner: ObjectIdentifier(self)))
    }

    func removed() {
        guard let services else { return }
        services.setTimer(self, at: nil) { _ in }
        services.tooltips.hide(owner: ObjectIdentifier(self), at: services.lastEventTime)
    }
}

struct HelpModifier: PrimitiveModifier {
    let text: String

    private func sync(_ node: ViewNode) {
        let s = (node.primitiveState as? HelpState) ?? HelpState(text: text)
        s.text = text
        s.services = node.environment._windowServices
        node.primitiveState = s
    }

    func _inserted(node: ViewNode) { sync(node) }
    func _updated(old: HelpModifier, node: ViewNode) { sync(node) }
    func _removed(node: ViewNode) { (node.primitiveState as? HelpState)?.removed() }
}

extension View {
    public func help(_ textKey: LocalizedStringKey) -> some View { help(Text(textKey)) }

    public func help(_ text: Text) -> some View {
        let s = text.plainString
        return modifier(HelpModifier(text: s)).accessibilityHint(Text(verbatim: s))
    }

    @_disfavoredOverload
    public func help<S: StringProtocol>(_ text: S) -> some View { help(Text(verbatim: String(text))) }
}

struct TooltipLayer: View {
    let center: TooltipCenter
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let tip = center.current {
            let palette = ControlPalette(scheme)
            TooltipPlacement(point: tip.point) {
                Text(verbatim: tip.text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .frame(maxWidth: TooltipMetrics.maxWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(palette.menuBackground)
                    .overlay { Rectangle().strokeBorder(palette.outline, lineWidth: 1) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

struct TooltipPlacement: Layout {
    let point: CGPoint

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let s = subviews.first else { return }
        let size = s.sizeThatFits(ProposedViewSize(width: min(TooltipMetrics.maxWidth + 14, bounds.width - 8), height: nil))
        var x = bounds.minX + point.x
        var y = bounds.minY + point.y + TooltipMetrics.offset
        x = max(bounds.minX + 4, min(x, bounds.maxX - size.width - 4))
        if y + size.height > bounds.maxY - 4 { y = bounds.minY + point.y - size.height - 6 }
        y = max(bounds.minY + 4, y)
        s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}
