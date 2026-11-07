import Foundation
import OVRender

package struct RenderEffectBehavior: PassthroughModifier {
    package init() {}
}

package struct NodeRenderEffectModifier: PrimitiveModifier {
    package let name: String
    package let effect: @MainActor () -> NodeRenderEffect

    package func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode] {
        content.map { c in
            let w = LayoutNode(RenderEffectBehavior(), children: [c])
            w.renderEffects = [effect()]
            return w
        }
    }
}

package struct MaskModifier<Mask: View>: PrimitiveModifier {
    package let mask: Mask
    package let alignment: Alignment

    package func _secondary(node: ViewNode) -> (any View)? { mask }

    package func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode] {
        content.map { c in
            let s = secondary()
            let layer: LayoutNode = s.count == 1 ? s[0] : (s.isEmpty ? .empty() : .zstack(alignment: alignment, s))
            let n = c.overlay(layer, alignment: alignment)
            n.renderEffects = [.mask]
            return n
        }
    }
}

public enum BlendMode: Hashable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight
    case difference, exclusion, hue, saturation, color, luminosity
    case sourceAtop, destinationOver, destinationOut, plusDarker, plusLighter

    package var render: RenderBlendMode {
        switch self {
        case .normal, .sourceAtop, .destinationOver, .destinationOut, .plusDarker: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .darken: return .darken
        case .lighten: return .lighten
        case .colorDodge: return .colorDodge
        case .colorBurn: return .colorBurn
        case .softLight: return .softLight
        case .hardLight: return .hardLight
        case .difference: return .difference
        case .exclusion: return .exclusion
        case .hue: return .hue
        case .saturation: return .saturation
        case .color: return .color
        case .luminosity: return .luminosity
        case .plusLighter: return .plusLighter
        }
    }
}

public enum ColorRenderingMode: Hashable, Sendable {
    case nonLinear, linear, extendedLinear
}

extension View {
    private func renderEffect(_ name: String, _ effect: @escaping @MainActor () -> NodeRenderEffect) -> some View {
        modifier(NodeRenderEffectModifier(name: name, effect: effect))
    }

    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some View {
        renderEffect("clipShape") { .clip({ shape.path(in: CGRect(origin: .zero, size: $0)) }, eoFill: style.isEOFilled) }
    }

    public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
    }

    public func mask<Mask: View>(alignment: Alignment = .center, @ViewBuilder _ mask: () -> Mask) -> some View {
        modifier(MaskModifier(mask: mask(), alignment: alignment))
    }

    @available(*, deprecated, message: "Use mask(alignment:_:) instead.")
    public func mask<Mask: View>(_ mask: Mask) -> some View {
        modifier(MaskModifier(mask: mask, alignment: .center))
    }

    public func blendMode(_ blendMode: BlendMode) -> some View {
        renderEffect("blendMode") { .blend(blendMode.render) }
    }

    public func compositingGroup() -> some View { renderEffect("compositingGroup") { .compositingGroup(isLayer: false) } }

    public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View {
        renderEffect("drawingGroup") { .compositingGroup(isLayer: true) }
    }

    public func shadow(color: Color = Color(.sRGBLinear, white: 0, opacity: 0.33), radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(ShadowModifier(color: color, radius: radius, x: x, y: y))
    }

    public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        renderEffect("blur") { .blur(radius: Double(radius)) }
    }

    public func colorMultiply(_ color: Color) -> some View { modifier(ColorMultiplyModifier(color: color)) }

    public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        background(Rectangle().fill(style))
    }

    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        background(shape.fill(style, style: fillStyle))
    }

    public func overlay<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        overlay(Rectangle().fill(style))
    }

    public func overlay<S: ShapeStyle, T: Shape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        overlay(shape.fill(style, style: fillStyle))
    }

    public func border<S: ShapeStyle>(_ content: S, width: CGFloat = 1) -> some View {
        overlay(Rectangle().strokeBorder(content, lineWidth: width))
    }
}

package struct ShadowModifier: PrimitiveModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat

    package func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode] {
        let c = color.resolve(in: node.environment).renderColor
        return content.map { n in
            let w = LayoutNode(RenderEffectBehavior(), children: [n])
            w.renderEffects = [.shadow(c, radius: Double(radius), x: Double(x), y: Double(y))]
            return w
        }
    }
}

package struct ColorMultiplyModifier: PrimitiveModifier {
    let color: Color

    package func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode] {
        let c = color.resolve(in: node.environment).renderColor
        return content.map { n in
            let w = LayoutNode(RenderEffectBehavior(), children: [n])
            w.renderEffects = [.colorMultiply(c)]
            return w
        }
    }
}
