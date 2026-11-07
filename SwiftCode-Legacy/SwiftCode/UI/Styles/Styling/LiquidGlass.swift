import SwiftUI
import AppKit

public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    public var isEmphasized: Bool

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        state: NSVisualEffectView.State = .active,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
        self.isEmphasized = isEmphasized
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        view.autoresizingMask = [.width, .height]
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

public struct SpecularBorder: View {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat
    public var lineWidth: CGFloat
    public var intensity: CGFloat

    public init(
        cornerRadius: CGFloat = 12,
        lineWidth: CGFloat = 1.0,
        intensity: CGFloat = 1.0
    ) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.intensity = intensity
    }

    public var body: some View {
        let topOpacity = (colorScheme == .dark ? 0.32 : 0.50) * intensity
        let midOpacity = (colorScheme == .dark ? 0.12 : 0.22) * intensity
        let bottomOpacity = (colorScheme == .dark ? 0.04 : 0.08) * intensity

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(topOpacity), location: 0.0),
                        .init(color: Color.white.opacity(midOpacity), location: 0.4),
                        .init(color: Color.white.opacity(bottomOpacity), location: 0.85),
                        .init(color: Color.white.opacity(bottomOpacity * 0.5), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
    }
}

public struct SpecularTopHighlight: View {
    @Environment(\.colorScheme) private var colorScheme
    public var cornerRadius: CGFloat
    public var height: CGFloat

    public init(cornerRadius: CGFloat = 12, height: CGFloat = 1.5) {
        self.cornerRadius = cornerRadius
        self.height = height
    }

    public var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.25 : 0.40),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: height
                )
                .blendMode(.plusLighter)
            Spacer(minLength: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}

public enum LiquidGlassStyle: String, Sendable, CaseIterable {
    case standard
    case prominent
    case subtle
    case sheet
    case sidebar
    case floatingBar
    case hud

    public var material: NSVisualEffectView.Material {
        switch self {
        case .standard: return .headerView
        case .prominent: return .contentBackground
        case .subtle: return .underWindowBackground
        case .sheet: return .sheet
        case .sidebar: return .sidebar
        case .floatingBar: return .popover
        case .hud: return .hudWindow
        }
    }

    public var blendingMode: NSVisualEffectView.BlendingMode {
        switch self {
        case .floatingBar, .hud: return .behindWindow
        default: return .withinWindow
        }
    }

    public var opacity: CGFloat {
        switch self {
        case .standard: return 0.88
        case .prominent: return 0.94
        case .subtle: return 0.75
        case .sheet: return 0.92
        case .sidebar: return 0.90
        case .floatingBar: return 0.85
        case .hud: return 0.95
        }
    }

    public var shadowRadius: CGFloat {
        switch self {
        case .standard: return 6
        case .prominent: return 12
        case .subtle: return 3
        case .sheet: return 16
        case .sidebar: return 0
        case .floatingBar: return 10
        case .hud: return 14
        }
    }

    public var shadowY: CGFloat {
        switch self {
        case .standard: return 2
        case .prominent: return 5
        case .subtle: return 1
        case .sheet: return 6
        case .sidebar: return 0
        case .floatingBar: return 4
        case .hud: return 6
        }
    }
}

public struct LiquidGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.liquidGlassEnabled) private var liquidGlassEnabled

    public var cornerRadius: CGFloat
    public var opacity: CGFloat
    public var blurRadius: CGFloat
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var tint: Color?
    public var showSpecularBorder: Bool
    public var borderWidth: CGFloat
    public var shadowRadius: CGFloat
    public var shadowY: CGFloat

    public init(
        cornerRadius: CGFloat = 12,
        opacity: CGFloat = 0.88,
        blurRadius: CGFloat = 20,
        material: NSVisualEffectView.Material = .headerView,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        tint: Color? = nil,
        showSpecularBorder: Bool = true,
        borderWidth: CGFloat = 1.0,
        shadowRadius: CGFloat = 6,
        shadowY: CGFloat = 2
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.material = material
        self.blendingMode = blendingMode
        self.tint = tint
        self.showSpecularBorder = showSpecularBorder
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public init(
        style: LiquidGlassStyle,
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        showSpecularBorder: Bool = true,
        borderWidth: CGFloat = 1.0
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = style.opacity
        self.blurRadius = 20
        self.material = style.material
        self.blendingMode = style.blendingMode
        self.tint = tint
        self.showSpecularBorder = showSpecularBorder
        self.borderWidth = borderWidth
        self.shadowRadius = style.shadowRadius
        self.shadowY = style.shadowY
    }

    public var body: some View {
        ZStack {
            if liquidGlassEnabled {
                VisualEffectView(
                    material: material,
                    blendingMode: blendingMode,
                    state: .active
                )
                .opacity(opacity)

                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(colorScheme == .dark ? 0.65 : 0.75)

                if let tint = tint {
                    tint.opacity(colorScheme == .dark ? 0.16 : 0.08)
                } else {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.22 : 0.12)
                }

                if showSpecularBorder {
                    SpecularBorder(cornerRadius: cornerRadius, lineWidth: borderWidth)
                    SpecularTopHighlight(cornerRadius: cornerRadius)
                }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(shadowRadius > 0 ? 0.35 : 0.0)
                : Color.black.opacity(shadowRadius > 0 ? 0.08 : 0.0),
            radius: shadowRadius,
            x: 0,
            y: shadowY
        )
    }
}

public struct LiquidGlassModifier: ViewModifier {
    @Environment(\.liquidGlassStyle) private var environmentStyle
    public var cornerRadius: CGFloat
    public var opacity: CGFloat
    public var blurRadius: CGFloat
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var tint: Color?
    public var showSpecularBorder: Bool
    public var borderWidth: CGFloat
    public var shadowRadius: CGFloat
    public var shadowY: CGFloat
    private var presetStyle: LiquidGlassStyle?

    public init(
        cornerRadius: CGFloat = 12,
        opacity: CGFloat = 0.88,
        blurRadius: CGFloat = 20,
        material: NSVisualEffectView.Material = .headerView,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        tint: Color? = nil,
        showSpecularBorder: Bool = true,
        borderWidth: CGFloat = 1.0,
        shadowRadius: CGFloat = 6,
        shadowY: CGFloat = 2
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.material = material
        self.blendingMode = blendingMode
        self.tint = tint
        self.showSpecularBorder = showSpecularBorder
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        self.presetStyle = nil
    }

    public init(
        style: LiquidGlassStyle,
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        showSpecularBorder: Bool = true,
        borderWidth: CGFloat = 1.0
    ) {
        self.cornerRadius = cornerRadius
        self.opacity = style.opacity
        self.blurRadius = 20
        self.material = style.material
        self.blendingMode = style.blendingMode
        self.tint = tint
        self.showSpecularBorder = showSpecularBorder
        self.borderWidth = borderWidth
        self.shadowRadius = style.shadowRadius
        self.shadowY = style.shadowY
        self.presetStyle = style
    }

    public func body(content: Content) -> some View {
        let useEnvironmentStyle = presetStyle == .standard && environmentStyle != .standard
        let effectiveStyle = useEnvironmentStyle ? environmentStyle : nil
        return content
            .background(
                LiquidGlassBackground(
                    cornerRadius: cornerRadius,
                    opacity: effectiveStyle?.opacity ?? opacity,
                    blurRadius: blurRadius,
                    material: effectiveStyle?.material ?? material,
                    blendingMode: effectiveStyle?.blendingMode ?? blendingMode,
                    tint: tint,
                    showSpecularBorder: showSpecularBorder,
                    borderWidth: borderWidth,
                    shadowRadius: effectiveStyle?.shadowRadius ?? shadowRadius,
                    shadowY: effectiveStyle?.shadowY ?? shadowY
                )
            )
    }
}

public struct LiquidGlassCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var padding: CGFloat
    public var style: LiquidGlassStyle
    public var tint: Color?
    public var borderWidth: CGFloat
    private var explicitMaterial: NSVisualEffectView.Material?
    private var explicitBlendingMode: NSVisualEffectView.BlendingMode?
    @ViewBuilder public var content: () -> Content

    public init(
        cornerRadius: CGFloat = 14,
        padding: CGFloat = 16,
        style: LiquidGlassStyle = .standard,
        tint: Color? = nil,
        borderWidth: CGFloat = 1.0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.style = style
        self.tint = tint
        self.borderWidth = borderWidth
        self.explicitMaterial = nil
        self.explicitBlendingMode = nil
        self.content = content
    }

    public init(
        cornerRadius: CGFloat = 14,
        padding: CGFloat = 16,
        material: NSVisualEffectView.Material = .headerView,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        tint: Color? = nil,
        borderWidth: CGFloat = 1.0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.style = .standard
        self.tint = tint
        self.borderWidth = borderWidth
        self.explicitMaterial = material
        self.explicitBlendingMode = blendingMode
        self.content = content
    }

    public var body: some View {
        Group {
            if let material = explicitMaterial {
                content()
                    .padding(padding)
                    .liquidGlass(
                        cornerRadius: cornerRadius,
                        material: material,
                        blendingMode: explicitBlendingMode ?? .withinWindow,
                        tint: tint,
                        borderWidth: borderWidth
                    )
            } else {
                content()
                    .padding(padding)
                    .liquidGlass(
                        style: style,
                        cornerRadius: cornerRadius,
                        tint: tint,
                        borderWidth: borderWidth
                    )
            }
        }
    }
}

public extension GroupBoxStyle where Self == LiquidGlassGroupBoxStyle {
    static var liquidGlass: LiquidGlassGroupBoxStyle {
        LiquidGlassGroupBoxStyle()
    }

    static func liquidGlass(
        style: LiquidGlassStyle = .standard,
        cornerRadius: CGFloat = 12,
        tint: Color? = nil
    ) -> LiquidGlassGroupBoxStyle {
        LiquidGlassGroupBoxStyle(cornerRadius: cornerRadius, style: style, tint: tint)
    }
}

public struct LiquidGlassGroupBoxStyle: GroupBoxStyle {
    public var cornerRadius: CGFloat
    public var style: LiquidGlassStyle
    public var tint: Color?

    public init(
        cornerRadius: CGFloat = 12,
        style: LiquidGlassStyle = .standard,
        tint: Color? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.headline)
            configuration.content
        }
        .padding()
        .liquidGlass(style: style, cornerRadius: cornerRadius, tint: tint)
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 12,
        opacity: CGFloat = 0.88,
        blurRadius: CGFloat = 20
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                opacity: opacity,
                blurRadius: blurRadius
            )
        )
    }

    func liquidGlass(
        style: LiquidGlassStyle = .standard,
        cornerRadius: CGFloat = 12,
        tint: Color? = nil,
        borderWidth: CGFloat = 1.0
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                style: style,
                cornerRadius: cornerRadius,
                tint: tint,
                borderWidth: borderWidth
            )
        )
    }

    func liquidGlass(
        cornerRadius: CGFloat = 12,
        material: NSVisualEffectView.Material = .headerView,
        blendingMode: NSVisualEffectView.BlendingMode = .withinWindow,
        tint: Color? = nil,
        borderWidth: CGFloat = 1.0,
        showSpecularBorder: Bool = true
    ) -> some View {
        modifier(
            LiquidGlassModifier(
                cornerRadius: cornerRadius,
                opacity: 0.88,
                blurRadius: 20,
                material: material,
                blendingMode: blendingMode,
                tint: tint,
                showSpecularBorder: showSpecularBorder,
                borderWidth: borderWidth
            )
        )
    }
}

private struct LiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct LiquidGlassDefaultStyleKey: EnvironmentKey {
    static let defaultValue: LiquidGlassStyle = .standard
}

public extension EnvironmentValues {
    var liquidGlassEnabled: Bool {
        get { self[LiquidGlassEnabledKey.self] }
        set { self[LiquidGlassEnabledKey.self] = newValue }
    }

    var liquidGlassStyle: LiquidGlassStyle {
        get { self[LiquidGlassDefaultStyleKey.self] }
        set { self[LiquidGlassDefaultStyleKey.self] = newValue }
    }
}

public extension View {
    func liquidGlassEnabled(_ enabled: Bool) -> some View {
        environment(\.liquidGlassEnabled, enabled)
    }

    func liquidGlassStyle(_ style: LiquidGlassStyle) -> some View {
        environment(\.liquidGlassStyle, style)
    }
}
